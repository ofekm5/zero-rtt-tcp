# destroy.ps1 - Tear down the baseline CDK stacks
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force
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

    if (-not $Force) {
        Write-Host "WARNING: This will destroy all baseline infrastructure (4 EC2 instances, VPC, subnets, etc.)"
        $Confirm = Read-Host "Are you sure? [y/N]"
        if ($Confirm -notmatch '^[Yy]$') {
            Write-Host "Aborted."
            exit 0
        }
    }

    Write-Host "[*] Destroying BaselineStack..."
    cdk destroy BaselineStack --force
    if ($LASTEXITCODE -ne 0) { exit 1 }

    Write-Host "[*] Destroying BaselinePacketTestStack..."
    cdk destroy BaselinePacketTestStack --force
    if ($LASTEXITCODE -ne 0) { exit 1 }

    Write-Host "[+] Destroy complete."

} finally {
    Pop-Location
}
