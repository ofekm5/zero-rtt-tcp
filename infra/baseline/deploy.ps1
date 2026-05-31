# deploy.ps1 - Deploy the baseline CDK stacks (plain kernel forwarding, no DPDK/Scapy)
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Bootstrap,
    [string[]]$CdkArgs = @()
)
$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
Push-Location $ScriptDir

try {
    $VenvDir = Join-Path $ScriptDir "..\..\venv"
    if (-not (Test-Path $VenvDir)) {
        Write-Host "[*] Creating virtual environment..."
        python -m venv $VenvDir
        if ($LASTEXITCODE -ne 0) { exit 1 }
    }

    $Activate = Join-Path $VenvDir "Scripts\Activate.ps1"
    . $Activate

    python -c "import aws_cdk" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[*] Installing CDK dependencies..."
        pip install -r requirements.txt
        if ($LASTEXITCODE -ne 0) { exit 1 }
    }

    if ($Bootstrap) {
        Write-Host "[*] Bootstrapping CDK environment..."
        cdk bootstrap
        if ($LASTEXITCODE -ne 0) { exit 1 }
    }

    Write-Host "[*] Deploying BaselinePacketTestStack and BaselineStack..."
    cdk deploy --all --require-approval never @CdkArgs
    if ($LASTEXITCODE -ne 0) { exit 1 }

    Write-Host ""
    Write-Host "[+] Deploy complete. Stack outputs:"
    aws cloudformation describe-stacks `
        --stack-name BaselineStack `
        --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" `
        --output table `
        --region eu-central-1

    Write-Host ""
    Write-Host "[*] Note: instances provision in ~2 minutes (no DPDK build)."
    Write-Host "    Run experiments/baseline-tcp/run_experiment.sh when all VMs are 'running'."

} finally {
    Pop-Location
}
