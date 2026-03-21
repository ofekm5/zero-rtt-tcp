from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_iam as iam,
    CfnOutput,
    Tags,
)
from constructs import Construct


class SmartNicsStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, vpc: ec2.IVpc, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create subnet selections for the chain topology
        client_subnet_selection = ec2.SubnetSelection(subnet_group_name="Client")
        middle_subnet_selection = ec2.SubnetSelection(subnet_group_name="Middle")
        server_subnet_selection = ec2.SubnetSelection(subnet_group_name="Server")

        # Get actual subnet IDs for ENI and route table configurations
        client_subnets = vpc.select_subnets(subnet_group_name="Client")
        middle_subnets = vpc.select_subnets(subnet_group_name="Middle")
        server_subnets = vpc.select_subnets(subnet_group_name="Server")

        # Base user data for Client/Server VMs (no Scapy, no DPDK — just git clone)
        base_user_data = ec2.UserData.for_linux()
        base_user_data.add_commands(
            "yum update -y",
            "yum install -y git",
            "GITHUB_TOKEN=$(aws ssm get-parameter --name /zero-rtt/github-token --with-decryption --query Parameter.Value --output text --region eu-central-1)",
            'git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-demo.git" /home/ec2-user/zero-rtt-demo',
            "chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-demo",
        )

        # User data for NIC VMs: DPDK 23.11 + hugepages + vfio-pci binding
        nic_user_data = ec2.UserData.for_linux()
        nic_user_data.add_commands(
            # System packages + DPDK build deps
            "yum update -y",
            "yum install -y git gcc make meson ninja-build python3-pyelftools "
            "numactl-devel kernel-devel libpcap-devel pciutils",
            # Clone repo
            "GITHUB_TOKEN=$(aws ssm get-parameter --name /zero-rtt/github-token "
            "--with-decryption --query Parameter.Value --output text --region eu-central-1)",
            'git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-demo.git" '
            "/home/ec2-user/zero-rtt-demo",
            "chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-demo",
            # Hugepages (512 x 2MB = 1 GiB)
            "echo 'vm.nr_hugepages=512' >> /etc/sysctl.conf",
            "sysctl -p",
            "mkdir -p /dev/hugepages",
            "mount -t hugetlbfs nodev /dev/hugepages",
            "echo 'nodev /dev/hugepages hugetlbfs defaults 0 0' >> /etc/fstab",
            # Build DPDK 23.11 (includes ENA PMD)
            "cd /opt",
            "curl -LO https://fast.dpdk.org/rel/dpdk-23.11.tar.xz",
            "tar xf dpdk-23.11.tar.xz",
            "cd dpdk-23.11",
            "meson setup build",
            "cd build && ninja && ninja install",
            "ldconfig",
            "echo '/usr/local/lib64' > /etc/ld.so.conf.d/dpdk.conf",
            "ldconfig",
            # vfio-pci driver (no-IOMMU mode for Nitro)
            "modprobe vfio-pci",
            "echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode",
            "echo 'vfio-pci' > /etc/modules-load.d/vfio.conf",
            # Bind secondary ENI (eth1) to DPDK
            "for i in $(seq 1 30); do",
            "    SECONDARY_PCI=$(basename $(readlink /sys/class/net/eth1/device) 2>/dev/null || true)",
            "    [ -n \"$SECONDARY_PCI\" ] && break",
            "    sleep 2",
            "done",
            "if [ -n \"$SECONDARY_PCI\" ]; then",
            "    ip link set eth1 down",
            "    dpdk-devbind.py --bind=vfio-pci $SECONDARY_PCI",
            "fi",
        )

        # Create IAM role for SSM access
        role = iam.Role(
            self,
            "SmartNicsRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                )
            ],
        )
        role.add_to_policy(iam.PolicyStatement(
            actions=["ssm:GetParameter"],
            resources=["arn:aws:ssm:eu-central-1:*:parameter/zero-rtt/*"],
        ))

        # Create security groups
        client_sg = ec2.SecurityGroup(
            self,
            "ClientSecurityGroup",
            vpc=vpc,
            description="Security group for Client VM",
            allow_all_outbound=True,
        )
        client_sg.add_ingress_rule(
            ec2.Peer.ipv4("10.1.0.0/16"),
            ec2.Port.all_traffic(),
            "Allow all traffic from VPC",
        )

        clientnic_sg = ec2.SecurityGroup(
            self,
            "ClientNicSecurityGroup",
            vpc=vpc,
            description="Security group for ClientNIC VM",
            allow_all_outbound=True,
        )
        clientnic_sg.add_ingress_rule(
            ec2.Peer.ipv4("10.1.0.0/16"),
            ec2.Port.all_traffic(),
            "Allow all traffic from VPC",
        )

        servernic_sg = ec2.SecurityGroup(
            self,
            "ServerNicSecurityGroup",
            vpc=vpc,
            description="Security group for ServerNIC VM",
            allow_all_outbound=True,
        )
        servernic_sg.add_ingress_rule(
            ec2.Peer.ipv4("10.1.0.0/16"),
            ec2.Port.all_traffic(),
            "Allow all traffic from VPC",
        )

        server_sg = ec2.SecurityGroup(
            self,
            "ServerSecurityGroup",
            vpc=vpc,
            description="Security group for Server VM",
            allow_all_outbound=True,
        )
        server_sg.add_ingress_rule(
            ec2.Peer.ipv4("10.1.0.0/16"),
            ec2.Port.all_traffic(),
            "Allow all traffic from VPC",
        )

        # Create Client VM in Client subnet
        client_instance = ec2.Instance(
            self,
            "ClientInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3, ec2.InstanceSize.MICRO
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            vpc=vpc,
            vpc_subnets=client_subnet_selection,
            security_group=client_sg,
            role=role,
            user_data=base_user_data,
            source_dest_check=False,  # Required: ClientNIC sends spoofed SYN-ACKs with server src IP
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/xvda",
                    volume=ec2.BlockDeviceVolume.ebs(
                        volume_size=30,
                        volume_type=ec2.EbsDeviceVolumeType.GP3,
                        delete_on_termination=True,
                    ),
                )
            ],
        )
        Tags.of(client_instance).add("Name", "smartnics-client")

        # Create Server VM in Server subnet
        server_instance = ec2.Instance(
            self,
            "ServerInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3, ec2.InstanceSize.MICRO
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            vpc=vpc,
            vpc_subnets=server_subnet_selection,
            security_group=server_sg,
            role=role,
            user_data=base_user_data,
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/xvda",
                    volume=ec2.BlockDeviceVolume.ebs(
                        volume_size=30,
                        volume_type=ec2.EbsDeviceVolumeType.GP3,
                        delete_on_termination=True,
                    ),
                )
            ],
        )
        Tags.of(server_instance).add("Name", "smartnics-server")

        # Create ClientNIC VM with 2 ENIs — c5n.large for DPDK performance
        # First ENI in Client subnet (eth0 = kernel/SSM, eth1 = DPDK data plane)
        clientnic_instance = ec2.Instance(
            self,
            "ClientNicInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.C5N, ec2.InstanceSize.LARGE
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            vpc=vpc,
            vpc_subnets=client_subnet_selection,
            security_group=clientnic_sg,
            role=role,
            user_data=nic_user_data,
            source_dest_check=False,  # Required for routing
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/xvda",
                    volume=ec2.BlockDeviceVolume.ebs(
                        volume_size=50,  # DPDK source + build artifacts
                        volume_type=ec2.EbsDeviceVolumeType.GP3,
                        delete_on_termination=True,
                    ),
                )
            ],
        )
        Tags.of(clientnic_instance).add("Name", "smartnics-clientnic")

        # Second ENI for ClientNIC in Middle subnet (bound to vfio-pci / DPDK)
        clientnic_middle_eni = ec2.CfnNetworkInterface(
            self,
            "ClientNicMiddleENI",
            subnet_id=middle_subnets.subnet_ids[0],
            group_set=[clientnic_sg.security_group_id],
            source_dest_check=False,
        )

        # Attach second ENI to ClientNIC
        ec2.CfnNetworkInterfaceAttachment(
            self,
            "ClientNicMiddleENIAttachment",
            device_index="1",
            instance_id=clientnic_instance.instance_id,
            network_interface_id=clientnic_middle_eni.ref,
        )

        # Create ServerNIC VM with 2 ENIs — c5n.large for DPDK performance
        # First ENI in Middle subnet (eth0 = kernel/SSM, eth1 = DPDK data plane)
        servernic_instance = ec2.Instance(
            self,
            "ServerNicInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.C5N, ec2.InstanceSize.LARGE
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            vpc=vpc,
            vpc_subnets=middle_subnet_selection,
            security_group=servernic_sg,
            role=role,
            user_data=nic_user_data,
            source_dest_check=False,  # Required for routing
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/xvda",
                    volume=ec2.BlockDeviceVolume.ebs(
                        volume_size=50,  # DPDK source + build artifacts
                        volume_type=ec2.EbsDeviceVolumeType.GP3,
                        delete_on_termination=True,
                    ),
                )
            ],
        )
        Tags.of(servernic_instance).add("Name", "smartnics-servernic")

        # Second ENI for ServerNIC in Server subnet (bound to vfio-pci / DPDK)
        servernic_server_eni = ec2.CfnNetworkInterface(
            self,
            "ServerNicServerENI",
            subnet_id=server_subnets.subnet_ids[0],
            group_set=[servernic_sg.security_group_id],
            source_dest_check=False,
        )

        # Attach second ENI to ServerNIC
        ec2.CfnNetworkInterfaceAttachment(
            self,
            "ServerNicServerENIAttachment",
            device_index="1",
            instance_id=servernic_instance.instance_id,
            network_interface_id=servernic_server_eni.ref,
        )

        # Configure routing tables
        # Force chain topology at the VPC network level so traffic cannot bypass NIC instances.
        # Each subnet's route table overrides the VPC local /16 route with more-specific /24
        # entries pointing at the appropriate NIC instance or ENI.

        # --- Client subnet ---
        client_route_table = ec2.CfnRouteTable(
            self,
            "ClientRouteTable",
            vpc_id=vpc.vpc_id,
        )
        ec2.CfnSubnetRouteTableAssociation(
            self,
            "ClientSubnetRTAssociation",
            route_table_id=client_route_table.ref,
            subnet_id=client_subnets.subnet_ids[0],
        )
        # Internet access (SSH)
        ec2.CfnRoute(
            self,
            "ClientIGWRoute",
            route_table_id=client_route_table.ref,
            destination_cidr_block="0.0.0.0/0",
            gateway_id=vpc.internet_gateway_id,
        )
        # Traffic to server subnet must pass through ClientNIC (eth0, primary ENI)
        ec2.CfnRoute(
            self,
            "ClientToServerViaNic",
            route_table_id=client_route_table.ref,
            destination_cidr_block="10.1.2.0/24",
            instance_id=clientnic_instance.instance_id,
        )

        # --- Middle subnet ---
        middle_route_table = ec2.CfnRouteTable(
            self,
            "MiddleRouteTable",
            vpc_id=vpc.vpc_id,
        )
        ec2.CfnSubnetRouteTableAssociation(
            self,
            "MiddleSubnetRTAssociation",
            route_table_id=middle_route_table.ref,
            subnet_id=middle_subnets.subnet_ids[0],
        )
        # Internet access (required at boot for git clone / DPDK build)
        ec2.CfnRoute(
            self,
            "MiddleIGWRoute",
            route_table_id=middle_route_table.ref,
            destination_cidr_block="0.0.0.0/0",
            gateway_id=vpc.internet_gateway_id,
        )
        # Forward-path: ClientNIC eth1 → ServerNIC eth0 (primary ENI, in middle subnet)
        ec2.CfnRoute(
            self,
            "MiddleToServerViaNic",
            route_table_id=middle_route_table.ref,
            destination_cidr_block="10.1.2.0/24",
            instance_id=servernic_instance.instance_id,
        )
        # Return-path: ServerNIC eth0 → ClientNIC eth1 (secondary ENI, in middle subnet)
        ec2.CfnRoute(
            self,
            "MiddleToClientViaNic",
            route_table_id=middle_route_table.ref,
            destination_cidr_block="10.1.0.0/24",
            network_interface_id=clientnic_middle_eni.ref,
        )

        # --- Server subnet ---
        server_route_table = ec2.CfnRouteTable(
            self,
            "ServerRouteTable",
            vpc_id=vpc.vpc_id,
        )
        ec2.CfnSubnetRouteTableAssociation(
            self,
            "ServerSubnetRTAssociation",
            route_table_id=server_route_table.ref,
            subnet_id=server_subnets.subnet_ids[0],
        )
        # Internet access (SSH)
        ec2.CfnRoute(
            self,
            "ServerIGWRoute",
            route_table_id=server_route_table.ref,
            destination_cidr_block="0.0.0.0/0",
            gateway_id=vpc.internet_gateway_id,
        )
        # Return traffic to client subnet must pass through ServerNIC eth1 (secondary ENI)
        ec2.CfnRoute(
            self,
            "ServerToClientViaNic",
            route_table_id=server_route_table.ref,
            destination_cidr_block="10.1.0.0/24",
            network_interface_id=servernic_server_eni.ref,
        )

        # Outputs
        CfnOutput(
            self,
            "ClientInstanceId",
            value=client_instance.instance_id,
            description="Client Instance ID",
        )
        CfnOutput(
            self,
            "ClientPublicIp",
            value=client_instance.instance_public_ip,
            description="Client Instance Public IP",
        )

        CfnOutput(
            self,
            "ClientNicInstanceId",
            value=clientnic_instance.instance_id,
            description="ClientNIC Instance ID",
        )
        CfnOutput(
            self,
            "ClientNicPublicIp",
            value=clientnic_instance.instance_public_ip,
            description="ClientNIC Instance Public IP",
        )

        CfnOutput(
            self,
            "ServerNicInstanceId",
            value=servernic_instance.instance_id,
            description="ServerNIC Instance ID",
        )
        CfnOutput(
            self,
            "ServerNicPublicIp",
            value=servernic_instance.instance_public_ip,
            description="ServerNIC Instance Public IP",
        )

        CfnOutput(
            self,
            "ServerInstanceId",
            value=server_instance.instance_id,
            description="Server Instance ID",
        )
        CfnOutput(
            self,
            "ServerPublicIp",
            value=server_instance.instance_public_ip,
            description="Server Instance Public IP",
        )
