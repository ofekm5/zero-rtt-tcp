from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_iam as iam,
    CfnOutput,
    Tags,
)
from constructs import Construct


class SmartNicsStack(Stack):
    """
    Baseline 4-VM chain: plain kernel IP forwarding, no DPDK, no Scapy middleware.

    Topology:
        Client (t3.micro, Client subnet)
          ↓ eth0 — kernel forwards via eth1
        ClientNIC (t3.micro, Client subnet primary / Middle subnet secondary)
          ↓ eth1 — VPC routes to ServerNIC
        ServerNIC (t3.micro, Middle subnet primary / Server subnet secondary)
          ↓ eth1 — directly connected to Server subnet
        Server (t3.micro, Server subnet)

    VMs are plain IP routers with ip_forward=1 and two static cross-subnet routes
    added at boot.  No DPDK build, no vfio-pci binding, no hugepages.
    Instances deploy in ~2 minutes (vs 15-20 min for DPDK stack).

    Static routes added in user data and persisted via
    /etc/sysconfig/network-scripts/route-ethX:
      ClientNIC eth1: 10.1.2.0/24 via 10.1.1.1   (Server subnet via Middle gateway)
      ServerNIC eth0: 10.1.0.0/24 via 10.1.1.1   (Client subnet via Middle gateway)
    """

    def __init__(self, scope: Construct, construct_id: str, vpc: ec2.IVpc, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        client_subnet_selection = ec2.SubnetSelection(subnet_group_name="Client")
        middle_subnet_selection = ec2.SubnetSelection(subnet_group_name="Middle")
        server_subnet_selection = ec2.SubnetSelection(subnet_group_name="Server")

        client_subnets = vpc.select_subnets(subnet_group_name="Client")
        middle_subnets = vpc.select_subnets(subnet_group_name="Middle")
        server_subnets = vpc.select_subnets(subnet_group_name="Server")

        # ── User data: Client and Server (no forwarding, just clone repo) ────────
        base_user_data = ec2.UserData.for_linux()
        base_user_data.add_commands(
            "yum update -y",
            "amazon-linux-extras install -y epel",
            "yum install -y git python3 python3-pip iperf",
            "GITHUB_TOKEN=$(aws ssm get-parameter --name /zero-rtt/github-token "
            "--with-decryption --query Parameter.Value --output text --region eu-central-1)",
            'git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" '
            "/home/ec2-user/zero-rtt-tcp",
            "chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp",
            "chmod -R 755 /home/ec2-user/zero-rtt-tcp",
        )

        # ── User data: ClientNIC ──────────────────────────────────────────────────
        # eth0: Client subnet (primary, SSM management + data plane)
        # eth1: Middle subnet (secondary, attached by CloudFormation)
        #
        # Static route: forward packets destined for the Server subnet (10.1.2.0/24)
        # out via eth1.  The VPC Middle-subnet route table then delivers the packet
        # to ServerNIC.  Route is persisted in route-eth1 so it survives a reboot.
        clientnic_user_data = ec2.UserData.for_linux()
        clientnic_user_data.add_commands(
            "yum update -y",
            "yum install -y git python3 python3-pip",
            "GITHUB_TOKEN=$(aws ssm get-parameter --name /zero-rtt/github-token "
            "--with-decryption --query Parameter.Value --output text --region eu-central-1)",
            'git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" '
            "/home/ec2-user/zero-rtt-tcp",
            "chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp",
            "chmod -R 755 /home/ec2-user/zero-rtt-tcp",
            # Enable IP forwarding
            "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf",
            "sysctl -p",
            # Wait for secondary ENI (eth1, Middle subnet) to appear
            "for i in $(seq 1 30); do",
            "    ip link show eth1 &>/dev/null && break",
            "    sleep 2",
            "done",
            # Bring up eth1 and get IP from DHCP
            "ip link set eth1 up",
            "dhclient eth1 2>/dev/null || true",
            # Persist static route: Server subnet via Middle gateway
            "mkdir -p /etc/sysconfig/network-scripts",
            "echo '10.1.2.0/24 via 10.1.1.1 dev eth1' > /etc/sysconfig/network-scripts/route-eth1",
            # Apply immediately (dhclient may not have run yet when this line executes,
            # but the route file ensures it is applied when eth1 comes up fully)
            "ip route add 10.1.2.0/24 via 10.1.1.1 dev eth1 2>/dev/null || true",
        )

        # ── User data: ServerNIC ──────────────────────────────────────────────────
        # eth0: Middle subnet (primary, SSM management + forward-path data plane)
        # eth1: Server subnet (secondary, attached by CloudFormation)
        #
        # Static route: forward return packets destined for the Client subnet
        # (10.1.0.0/24) out via eth0.  The VPC Middle-subnet route table delivers
        # the packet to ClientNIC eth1.
        servernic_user_data = ec2.UserData.for_linux()
        servernic_user_data.add_commands(
            "yum update -y",
            "yum install -y git python3 python3-pip",
            "GITHUB_TOKEN=$(aws ssm get-parameter --name /zero-rtt/github-token "
            "--with-decryption --query Parameter.Value --output text --region eu-central-1)",
            'git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" '
            "/home/ec2-user/zero-rtt-tcp",
            "chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp",
            "chmod -R 755 /home/ec2-user/zero-rtt-tcp",
            # Enable IP forwarding
            "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf",
            "sysctl -p",
            # Wait for secondary ENI (eth1, Server subnet) to appear
            "for i in $(seq 1 30); do",
            "    ip link show eth1 &>/dev/null && break",
            "    sleep 2",
            "done",
            # Bring up eth1 and get IP from DHCP
            "ip link set eth1 up",
            "dhclient eth1 2>/dev/null || true",
            # Persist static route: Client subnet via Middle gateway
            "mkdir -p /etc/sysconfig/network-scripts",
            "echo '10.1.0.0/24 via 10.1.1.1 dev eth0' > /etc/sysconfig/network-scripts/route-eth0",
            "ip route add 10.1.0.0/24 via 10.1.1.1 dev eth0 2>/dev/null || true",
        )

        # ── IAM role (SSM + GitHub token) ────────────────────────────────────────
        role = iam.Role(
            self,
            "BaselineRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
            ],
        )
        role.add_to_policy(iam.PolicyStatement(
            actions=["ssm:GetParameter"],
            resources=["arn:aws:ssm:eu-central-1:*:parameter/zero-rtt/*"],
        ))
        # GitHub PAT for cloning the private repo lives in Secrets Manager
        # (zero-rtt/github-token) — the legacy SSM parameter token is expired,
        # so the user-data clone fails at boot and the VMs come up with no repo.
        # The experiment orchestrators clone on demand to self-heal that, but
        # only if the instance role can actually read the secret. Without this
        # grant the baseline stack cannot run any experiment at all; the DPDK
        # stack has carried the same statement since the token was rotated.
        role.add_to_policy(iam.PolicyStatement(
            actions=["secretsmanager:GetSecretValue"],
            resources=[
                "arn:aws:secretsmanager:eu-central-1:*:secret:zero-rtt/github-token*"
            ],
        ))

        # ── Security groups ───────────────────────────────────────────────────────
        def make_sg(name, desc):
            sg = ec2.SecurityGroup(self, name, vpc=vpc, description=desc, allow_all_outbound=True)
            sg.add_ingress_rule(ec2.Peer.ipv4("10.1.0.0/16"), ec2.Port.all_traffic(), "VPC traffic")
            return sg

        client_sg    = make_sg("ClientSG",    "Security group for baseline Client VM")
        clientnic_sg = make_sg("ClientNicSG", "Security group for baseline ClientNIC VM")
        servernic_sg = make_sg("ServerNicSG", "Security group for baseline ServerNIC VM")
        server_sg    = make_sg("ServerSG",    "Security group for baseline Server VM")

        ebs_30 = [ec2.BlockDevice(
            device_name="/dev/xvda",
            volume=ec2.BlockDeviceVolume.ebs(
                30, volume_type=ec2.EbsDeviceVolumeType.GP3, delete_on_termination=True,
            ),
        )]

        # ── Client VM ────────────────────────────────────────────────────────────
        client_instance = ec2.Instance(
            self, "ClientInstance",
            instance_type=ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            vpc=vpc,
            vpc_subnets=client_subnet_selection,
            security_group=client_sg,
            role=role,
            user_data=base_user_data,
            source_dest_check=False,
            block_devices=ebs_30,
        )
        Tags.of(client_instance).add("Name", "baseline-client")

        # ── Server VM ────────────────────────────────────────────────────────────
        server_instance = ec2.Instance(
            self, "ServerInstance",
            instance_type=ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            vpc=vpc,
            vpc_subnets=server_subnet_selection,
            security_group=server_sg,
            role=role,
            user_data=base_user_data,
            block_devices=ebs_30,
        )
        Tags.of(server_instance).add("Name", "baseline-server")

        # ── ClientNIC VM — eth0 in Client subnet, eth1 in Middle subnet ──────────
        clientnic_instance = ec2.Instance(
            self, "ClientNicInstance",
            instance_type=ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            vpc=vpc,
            vpc_subnets=client_subnet_selection,
            security_group=clientnic_sg,
            role=role,
            user_data=clientnic_user_data,
            source_dest_check=False,
            block_devices=ebs_30,
        )
        Tags.of(clientnic_instance).add("Name", "baseline-clientnic")

        clientnic_middle_eni = ec2.CfnNetworkInterface(
            self, "ClientNicMiddleENI",
            subnet_id=middle_subnets.subnet_ids[0],
            group_set=[clientnic_sg.security_group_id],
            source_dest_check=False,
        )
        ec2.CfnNetworkInterfaceAttachment(
            self, "ClientNicMiddleENIAttachment",
            device_index="1",
            instance_id=clientnic_instance.instance_id,
            network_interface_id=clientnic_middle_eni.ref,
        )

        # ── ServerNIC VM — eth0 in Middle subnet, eth1 in Server subnet ──────────
        servernic_instance = ec2.Instance(
            self, "ServerNicInstance",
            instance_type=ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            vpc=vpc,
            vpc_subnets=middle_subnet_selection,
            security_group=servernic_sg,
            role=role,
            user_data=servernic_user_data,
            source_dest_check=False,
            block_devices=ebs_30,
        )
        Tags.of(servernic_instance).add("Name", "baseline-servernic")

        servernic_server_eni = ec2.CfnNetworkInterface(
            self, "ServerNicServerENI",
            subnet_id=server_subnets.subnet_ids[0],
            group_set=[servernic_sg.security_group_id],
            source_dest_check=False,
        )
        ec2.CfnNetworkInterfaceAttachment(
            self, "ServerNicServerENIAttachment",
            device_index="1",
            instance_id=servernic_instance.instance_id,
            network_interface_id=servernic_server_eni.ref,
        )

        # ── VPC Route tables ──────────────────────────────────────────────────────
        # Force the 4-VM chain at the VPC level. More-specific /24 routes override
        # the VPC local /16 route for each subnet.

        # Client subnet: traffic to Server subnet must enter via ClientNIC eth0
        client_rt = ec2.CfnRouteTable(self, "ClientRouteTable", vpc_id=vpc.vpc_id)
        ec2.CfnSubnetRouteTableAssociation(
            self, "ClientSubnetRTA",
            route_table_id=client_rt.ref,
            subnet_id=client_subnets.subnet_ids[0],
        )
        ec2.CfnRoute(self, "ClientIGWRoute",
            route_table_id=client_rt.ref,
            destination_cidr_block="0.0.0.0/0",
            gateway_id=vpc.internet_gateway_id,
        )
        ec2.CfnRoute(self, "ClientToServerViaNic",
            route_table_id=client_rt.ref,
            destination_cidr_block="10.1.2.0/24",
            instance_id=clientnic_instance.instance_id,
        )

        # Middle subnet:
        #   forward-path  10.1.2.0/24 → ServerNIC (instance, VPC picks eth0 in Middle)
        #   return-path   10.1.0.0/24 → ClientNIC eth1 (specific ENI in Middle subnet)
        middle_rt = ec2.CfnRouteTable(self, "MiddleRouteTable", vpc_id=vpc.vpc_id)
        ec2.CfnSubnetRouteTableAssociation(
            self, "MiddleSubnetRTA",
            route_table_id=middle_rt.ref,
            subnet_id=middle_subnets.subnet_ids[0],
        )
        ec2.CfnRoute(self, "MiddleIGWRoute",
            route_table_id=middle_rt.ref,
            destination_cidr_block="0.0.0.0/0",
            gateway_id=vpc.internet_gateway_id,
        )
        ec2.CfnRoute(self, "MiddleToServerViaNic",
            route_table_id=middle_rt.ref,
            destination_cidr_block="10.1.2.0/24",
            instance_id=servernic_instance.instance_id,
        )
        ec2.CfnRoute(self, "MiddleToClientViaNic",
            route_table_id=middle_rt.ref,
            destination_cidr_block="10.1.0.0/24",
            network_interface_id=clientnic_middle_eni.ref,
        )

        # Server subnet: return traffic to Client subnet enters via ServerNIC eth1
        server_rt = ec2.CfnRouteTable(self, "ServerRouteTable", vpc_id=vpc.vpc_id)
        ec2.CfnSubnetRouteTableAssociation(
            self, "ServerSubnetRTA",
            route_table_id=server_rt.ref,
            subnet_id=server_subnets.subnet_ids[0],
        )
        ec2.CfnRoute(self, "ServerIGWRoute",
            route_table_id=server_rt.ref,
            destination_cidr_block="0.0.0.0/0",
            gateway_id=vpc.internet_gateway_id,
        )
        ec2.CfnRoute(self, "ServerToClientViaNic",
            route_table_id=server_rt.ref,
            destination_cidr_block="10.1.0.0/24",
            network_interface_id=servernic_server_eni.ref,
        )

        # ── Outputs ───────────────────────────────────────────────────────────────
        for logical, iid, desc in [
            ("ClientInstanceId",    client_instance.instance_id,    "Client Instance ID"),
            ("ClientPublicIp",      client_instance.instance_public_ip, "Client Public IP"),
            ("ClientNicInstanceId", clientnic_instance.instance_id, "ClientNIC Instance ID"),
            ("ClientNicPublicIp",   clientnic_instance.instance_public_ip, "ClientNIC Public IP"),
            ("ServerNicInstanceId", servernic_instance.instance_id, "ServerNIC Instance ID"),
            ("ServerNicPublicIp",   servernic_instance.instance_public_ip, "ServerNIC Public IP"),
            ("ServerInstanceId",    server_instance.instance_id,    "Server Instance ID"),
            ("ServerPublicIp",      server_instance.instance_public_ip, "Server Public IP"),
        ]:
            CfnOutput(self, logical, value=iid, description=desc)
