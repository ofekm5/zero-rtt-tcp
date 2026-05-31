#!/usr/bin/env python3
import os
import aws_cdk as cdk
from cdk.smartnics_stack import SmartNicsStack
from cdk.packet_test_stack import PacketTestStack


app = cdk.App()

packet_test_stack = PacketTestStack(
    app,
    "BaselinePacketTestStack",
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region="eu-central-1",
    ),
)

SmartNicsStack(
    app,
    "BaselineStack",
    vpc=packet_test_stack.vpc,
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region="eu-central-1",
    ),
)

app.synth()
