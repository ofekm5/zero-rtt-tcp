from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_iam as iam,
    CfnOutput,
    Tags,
)
from constructs import Construct


def _bind_data_enis_to_vfio(expected_enis: int) -> list:
    """User-data lines that bind every non-primary ENI to vfio-pci.

    ENIs are identified by MAC via IMDS, not by kernel interface name. Naming is
    unreliable here on two counts: the Middle-subnet and endpoint-subnet ENIs are
    not guaranteed to come up as eth1/eth2 in device_index order, and unbinding
    one ENI frees its name for a later-arriving one. Both make a name-keyed bind
    loop attach DPDK to the wrong link — or to none, if the name it waits for
    never appears. IMDS `device-number` is the authoritative role signal, so
    device-number 0 (primary, kernel/SSM) is skipped and everything else is bound.
    """
    return [
        "TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token"
        " -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')",
        "IMDS=http://169.254.169.254/latest/meta-data/network/interfaces/macs",
        # Wait for every ENI to be attached AND to have a kernel netdev we can
        # read its PCI address from.
        "for i in $(seq 1 60); do",
        "    MACS=$(curl -s -H \"X-aws-ec2-metadata-token: $TOKEN\" $IMDS/ | tr -d '/')",
        "    READY=1",
        f"    [ $(echo $MACS | wc -w) -ge {expected_enis} ] || READY=0",
        "    for MAC in $MACS; do",
        "        grep -qi \"^$MAC$\" /sys/class/net/*/address 2>/dev/null || READY=0",
        "    done",
        "    [ \"$READY\" = \"1\" ] && break",
        "    sleep 2",
        "done",
        f"echo \"vfio-bind: expected {expected_enis} ENIs, IMDS reports $(echo $MACS | wc -w)\"",
        # Bind each non-primary ENI. Resolve name->PCI immediately before the
        # unbind so a rename in between cannot redirect us to another device.
        "for MAC in $MACS; do",
        "    DEV=$(curl -s -H \"X-aws-ec2-metadata-token: $TOKEN\" $IMDS/$MAC/device-number)",
        "    if [ \"$DEV\" = \"0\" ]; then",
        "        echo \"vfio-bind: skipping primary ENI $MAC (kernel/SSM)\"",
        "        continue",
        "    fi",
        "    IFACE=$(grep -li \"^$MAC$\" /sys/class/net/*/address 2>/dev/null | head -1 | cut -d/ -f5)",
        "    if [ -z \"$IFACE\" ]; then",
        "        echo \"vfio-bind: ERROR no netdev for ENI $MAC (device-number $DEV)\"",
        "        continue",
        "    fi",
        "    PCI=$(basename $(readlink /sys/class/net/$IFACE/device))",
        "    echo \"vfio-bind: ENI $MAC (device-number $DEV) = $IFACE = $PCI -> vfio-pci\"",
        "    ip link set $IFACE down",
        "    dpdk-devbind.py --bind=vfio-pci $PCI",
        "done",
        "dpdk-devbind.py --status | grep -A5 'Network devices using DPDK'",
    ]


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

        # Base user data for Client/Server VMs (no Scapy, no DPDK — just git clone + bpftrace)
        base_user_data = ec2.UserData.for_linux()
        base_user_data.add_commands(
            "yum update -y",
            "amazon-linux-extras install -y epel",
            "yum install -y git iperf",
            "amazon-linux-extras install -y BCC",
            "yum install -y bpftrace",
            "GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '\"[:space:]')",
            'git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/ec2-user/zero-rtt-tcp',
            "chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp",
            "chmod -R 755 /home/ec2-user/zero-rtt-tcp",
        )

        # User data for ServerNIC VM: DPDK 23.11 + hugepages + vfio-pci + servernic-dpdk build
        #
        # ENI role pinning (design D1, dual-DPDK):
        #   eth0: primary ENI (Middle subnet, kernel) — SSM management only
        #   eth1: secondary ENI (Middle subnet, DPDK) — ClientNIC-facing data plane (vfio-pci)
        #   eth2: tertiary ENI (Server subnet, DPDK)  — Server-facing data plane (vfio-pci)
        servernic_user_data = ec2.UserData.for_linux()
        servernic_user_data.add_commands(
            # System packages
            "yum update -y",
            "yum install -y git gcc make numactl-devel kernel-devel libpcap-devel pciutils python3-pip",
            # Clone repo
            "GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token "
            "--query SecretString --output text --region eu-central-1 | tr -d '\"[:space:]')",
            'git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" '
            "/home/ec2-user/zero-rtt-tcp",
            "chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp",
            "chmod -R 755 /home/ec2-user/zero-rtt-tcp",
            # Enable IP forwarding
            "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf",
            "sysctl -p",
            # Hugepages (512 x 2 MB = 1 GiB)
            "echo 'vm.nr_hugepages=512' >> /etc/sysctl.conf",
            "sysctl -p",
            "mkdir -p /dev/hugepages",
            "mount -t hugetlbfs nodev /dev/hugepages",
            "echo 'nodev /dev/hugepages hugetlbfs defaults 0 0' >> /etc/fstab",
            # Swap (4 GB) to survive DPDK build on c5n.large
            "fallocate -l 4G /swapfile",
            "chmod 600 /swapfile",
            "mkswap /swapfile",
            "swapon /swapfile",
            "echo '/swapfile swap swap defaults 0 0' >> /etc/fstab",
            # Build tools
            "pip3 install meson ninja pyelftools",
            # Build DPDK 23.11
            "cd /opt",
            "curl -LO https://fast.dpdk.org/rel/dpdk-23.11.tar.xz",
            "tar xf dpdk-23.11.tar.xz",
            "cd dpdk-23.11",
            "/usr/local/bin/meson setup build -Dplatform=generic",
            "cd build && /usr/local/bin/ninja -j1 && /usr/local/bin/ninja install",
            "echo '/usr/local/lib64' > /etc/ld.so.conf.d/dpdk.conf",
            "ldconfig",
            "echo 'export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}' > /etc/profile.d/dpdk.sh",
            "modprobe vfio-pci",
            "echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode",
            "echo 'vfio-pci' > /etc/modules-load.d/vfio.conf",
            *_bind_data_enis_to_vfio(expected_enis=3),
            # Build servernic-dpdk application
            "export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig",
            "cd /home/ec2-user/zero-rtt-tcp/src/servernic/dpdk",
            "/usr/local/bin/meson setup builddir",
            "cd builddir && /usr/local/bin/ninja",
            "chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp/src/servernic/dpdk/builddir",
        )

        # User data for ClientNIC VM: DPDK 23.11 + hugepages + vfio-pci + clientnic-dpdk build
        #
        # Key fixes vs naive approach:
        #   - pip3 meson/ninja/pyelftools: yum ninja-build is 1.7.2, DPDK needs >=1.8.2;
        #     yum python3-pyelftools doesn't populate the Python module path correctly.
        #   - 4 GB swap added before build: DPDK 23.11 has 685 targets; without swap the
        #     OOM killer terminates the compiler mid-build on a 4.9 GB instance.
        #   - ninja -j1: limits peak RSS; parallel jobs push resident set over the limit.
        #   - ldconfig.conf written before ldconfig: so the runtime linker finds librte_*.
        #   - PKG_CONFIG_PATH persisted to /etc/profile.d: meson needs to find libdpdk.pc
        #     at /usr/local/lib64/pkgconfig when building clientnic-dpdk.
        #   - -Dplatform=generic: avoids CPU-feature probing that fails inside cloud VMs.
        clientnic_user_data = ec2.UserData.for_linux()
        clientnic_user_data.add_commands(
            # System packages
            "yum update -y",
            "yum install -y git gcc make numactl-devel kernel-devel libpcap-devel pciutils python3-pip",
            # Clone repo
            "GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token "
            "--query SecretString --output text --region eu-central-1 | tr -d '\"[:space:]')",
            'git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" '
            "/home/ec2-user/zero-rtt-tcp",
            "chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp",
            "chmod -R 755 /home/ec2-user/zero-rtt-tcp",
            # Enable IP forwarding
            "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf",
            "sysctl -p",
            # Hugepages (512 x 2 MB = 1 GiB)
            "echo 'vm.nr_hugepages=512' >> /etc/sysctl.conf",
            "sysctl -p",
            "mkdir -p /dev/hugepages",
            "mount -t hugetlbfs nodev /dev/hugepages",
            "echo 'nodev /dev/hugepages hugetlbfs defaults 0 0' >> /etc/fstab",
            # Swap (4 GB) — must be created before ninja to avoid OOM on c5n.large
            "fallocate -l 4G /swapfile",
            "chmod 600 /swapfile",
            "mkswap /swapfile",
            "swapon /swapfile",
            "echo '/swapfile swap swap defaults 0 0' >> /etc/fstab",
            # Build tools — pip3 versions required (yum packages too old or broken)
            "pip3 install meson ninja pyelftools scapy",
            # Build DPDK 23.11 with -j1 to stay within memory budget
            "cd /opt",
            "curl -LO https://fast.dpdk.org/rel/dpdk-23.11.tar.xz",
            "tar xf dpdk-23.11.tar.xz",
            "cd dpdk-23.11",
            "/usr/local/bin/meson setup build -Dplatform=generic",
            "cd build && /usr/local/bin/ninja -j1 && /usr/local/bin/ninja install",
            # Linker and pkg-config paths (order matters: conf file before ldconfig)
            "echo '/usr/local/lib64' > /etc/ld.so.conf.d/dpdk.conf",
            "ldconfig",
            "echo 'export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}' > /etc/profile.d/dpdk.sh",
            # vfio-pci driver (no-IOMMU mode for AWS Nitro — no IOMMU exposed to guest)
            "modprobe vfio-pci",
            "echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode",
            "echo 'vfio-pci' > /etc/modules-load.d/vfio.conf",
            *_bind_data_enis_to_vfio(expected_enis=3),
            # Build clientnic-dpdk-forwarder application (stamps V, no translation)
            "export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig",
            "cd /home/ec2-user/zero-rtt-tcp/src/clientnic/dpdk-forwarder",
            "/usr/local/bin/meson setup builddir",
            "cd builddir && /usr/local/bin/ninja",
            "chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp/src/clientnic/dpdk-forwarder/builddir",
            "ln -sf /home/ec2-user/zero-rtt-tcp/src/clientnic/dpdk-forwarder/builddir/clientnic-dpdk-forwarder"
            " /home/ec2-user/zero-rtt-tcp/src/clientnic/dpdk-active",
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
        # GitHub PAT for cloning the private repo lives in Secrets Manager
        # (zero-rtt/github-token) — the legacy SSM parameter token is expired.
        role.add_to_policy(iam.PolicyStatement(
            actions=["secretsmanager:GetSecretValue"],
            resources=[
                "arn:aws:secretsmanager:eu-central-1:*:secret:zero-rtt/github-token*"
            ],
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
                ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE
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
                ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE
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

        # Create ClientNIC VM with 3 ENIs — c5n.large for DPDK performance
        # ENI role pinning (design D1, dual-DPDK):
        #   eth0: primary ENI (Client subnet, kernel) — SSM management only
        #   eth1: secondary ENI (Middle subnet, DPDK)  — ServerNIC-facing data plane (vfio-pci)
        #   eth2: tertiary ENI (Client subnet, DPDK)   — Client-facing data plane (vfio-pci)
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
            user_data=clientnic_user_data,
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

        # Secondary ENI for ClientNIC in Middle subnet (bound to vfio-pci / DPDK)
        clientnic_middle_eni = ec2.CfnNetworkInterface(
            self,
            "ClientNicMiddleENI",
            subnet_id=middle_subnets.subnet_ids[0],
            group_set=[clientnic_sg.security_group_id],
            source_dest_check=False,
        )

        # Attach secondary ENI (eth1, device_index=1) to ClientNIC
        ec2.CfnNetworkInterfaceAttachment(
            self,
            "ClientNicMiddleENIAttachment",
            device_index="1",
            instance_id=clientnic_instance.instance_id,
            network_interface_id=clientnic_middle_eni.ref,
        )

        # Tertiary ENI for ClientNIC in Client subnet (eth2 = Client-facing DPDK data
        # plane, moved off the primary so the primary can stay kernel/SSM-only)
        clientnic_client_eni = ec2.CfnNetworkInterface(
            self,
            "ClientNicClientENI",
            subnet_id=client_subnets.subnet_ids[0],
            group_set=[clientnic_sg.security_group_id],
            source_dest_check=False,
        )

        # Attach tertiary ENI (eth2, device_index=2) to ClientNIC
        ec2.CfnNetworkInterfaceAttachment(
            self,
            "ClientNicClientENIAttachment",
            device_index="2",
            instance_id=clientnic_instance.instance_id,
            network_interface_id=clientnic_client_eni.ref,
        )

        # Create ServerNIC VM with 3 ENIs — c5n.large for DPDK performance
        # ENI role pinning (design D1, dual-DPDK):
        #   eth0: primary ENI (Middle subnet, kernel) — SSM management only
        #   eth1: secondary ENI (Middle subnet, DPDK)  — ClientNIC-facing data plane (vfio-pci)
        #   eth2: tertiary ENI (Server subnet, DPDK)   — Server-facing data plane (vfio-pci)
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
            user_data=servernic_user_data,
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

        # Secondary ENI for ServerNIC in Middle subnet (eth1 = ClientNIC-facing DPDK port)
        servernic_middle_eni = ec2.CfnNetworkInterface(
            self,
            "ServerNicMiddleENI",
            subnet_id=middle_subnets.subnet_ids[0],
            group_set=[servernic_sg.security_group_id],
            source_dest_check=False,
        )

        # Attach secondary ENI (eth1, device_index=1) to ServerNIC
        ec2.CfnNetworkInterfaceAttachment(
            self,
            "ServerNicMiddleENIAttachment",
            device_index="1",
            instance_id=servernic_instance.instance_id,
            network_interface_id=servernic_middle_eni.ref,
        )

        # Tertiary ENI for ServerNIC in Server subnet (eth2 = Server-facing DPDK data plane)
        servernic_server_eni = ec2.CfnNetworkInterface(
            self,
            "ServerNicServerENI",
            subnet_id=server_subnets.subnet_ids[0],
            group_set=[servernic_sg.security_group_id],
            source_dest_check=False,
        )

        # Attach tertiary ENI (eth2, device_index=2) to ServerNIC
        ec2.CfnNetworkInterfaceAttachment(
            self,
            "ServerNicServerENIAttachment",
            device_index="2",
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
        # Traffic to server subnet must pass through ClientNIC (eth2, client-facing DPDK ENI)
        ec2.CfnRoute(
            self,
            "ClientToServerViaNic",
            route_table_id=client_route_table.ref,
            destination_cidr_block="10.1.2.0/24",
            network_interface_id=clientnic_client_eni.ref,
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
        # Forward-path: ClientNIC eth1 → ServerNIC eth1 (secondary ENI, Middle subnet, DPDK)
        ec2.CfnRoute(
            self,
            "MiddleToServerViaNic",
            route_table_id=middle_route_table.ref,
            destination_cidr_block="10.1.2.0/24",
            network_interface_id=servernic_middle_eni.ref,
        )
        # Return-path: ServerNIC eth1 → ClientNIC eth1 (secondary ENI, in middle subnet)
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
