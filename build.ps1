#Requires -Version 5.1
<#
.SYNOPSIS
Builds the Chocolatey Test Environment Vagrant box for one provider.

.EXAMPLE
.\build.ps1 -Provider hyperv -Version 3.4.0

.EXAMPLE
.\build.ps1 -Provider virtualbox -Version 3.4.0 -IsoUrl D:\ISOs\17763.3650.221105-1748.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateSet('hyperv', 'virtualbox')]
  [string]$Provider,

  [Parameter(Mandatory)]
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$Version,

  # Defaults to the Microsoft evaluation download defined in the template.
  # Pass a local path to skip the ~5.3 GB download.
  [string]$IsoUrl,

  [string]$IsoChecksum,

  [string]$HyperVSwitchName,

  [switch]$ShowWindow,

  # vCPUs for the build VM only (the box runs with 2; see the Vagrantfile template).
  # Use 1 for VirtualBox in NEM mode, where multi-vCPU Windows guests can hang at boot.
  [ValidateRange(1, 64)]
  [int]$Cpus,

  # Packer's -on-error. 'abort' leaves a failed build VM in place for inspection
  # (remove it yourself afterwards); the default deletes it.
  [ValidateSet('cleanup', 'abort', 'ask')]
  [string]$OnError = 'cleanup'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this from an elevated PowerShell prompt (Hyper-V and the Hyper-V builder require it).'
}

# The template delivers its answer file on a CD, which needs an ISO authoring tool.
if (-not (Get-Command oscdimg.exe, xorriso.exe -ErrorAction SilentlyContinue)) {
  $adkOscdimg = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
  if (Test-Path "$adkOscdimg\oscdimg.exe") {
    $env:Path = "$adkOscdimg;$env:Path"
  }
  else {
    throw 'oscdimg.exe not found. Install the Windows ADK "Deployment Tools" feature: https://learn.microsoft.com/windows-hardware/get-started/adk-install'
  }
}

$hypervisorRunning = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
if ($Provider -eq 'virtualbox' -and $hypervisorRunning) {
  Write-Warning ('The Windows hypervisor is running, so VirtualBox will run on top of it (NEM mode): slower, but the box it produces is the same. ' +
    'To build natively instead, the hypervisor must not load at boot: "bcdedit /set hypervisorlaunchtype off" is not enough on its own ' +
    'if virtualization-based security is on (memory integrity, Credential Guard, Windows Hello enhanced sign-in), because VBS launches the hypervisor anyway. See README.md.')
}
if ($Provider -eq 'hyperv' -and -not $hypervisorRunning) {
  throw 'The Windows hypervisor is not running. Run "bcdedit /set hypervisorlaunchtype auto" and reboot.'
}

$source = @{ hyperv = 'hyperv-iso.hyperv'; virtualbox = 'virtualbox-iso.virtualbox' }[$Provider]
$packerArgs = @('build', "-only=$source", "-on-error=$OnError", '-var', "image_version=$Version")
if ($IsoUrl) { $packerArgs += '-var', "iso_url=$IsoUrl" }
if ($IsoChecksum) { $packerArgs += '-var', "iso_checksum=$IsoChecksum" }
if ($HyperVSwitchName) { $packerArgs += '-var', "hyperv_switch_name=$HyperVSwitchName" }
if ($ShowWindow) { $packerArgs += '-var', 'headless=false' }
if ($Cpus) { $packerArgs += '-var', "build_cpus=$Cpus" }
$packerArgs += '.'

New-Item -ItemType Directory -Force -Path logs | Out-Null
$env:PACKER_LOG = '1'
$env:PACKER_LOG_PATH = Join-Path $PSScriptRoot ("logs\packer-{0}-{1}-{2:yyyyMMdd-HHmmss}.log" -f $Provider, $Version, (Get-Date))

& packer init .
if ($LASTEXITCODE) { throw "packer init failed ($LASTEXITCODE)" }
& packer validate -only="$source" -var "image_version=$Version" .
if ($LASTEXITCODE) { throw "packer validate failed ($LASTEXITCODE)" }

# Packer's checksum post-processor appends to an existing file, so a rebuild
# would leave the previous box's hash in it as well.
$checksumFile = Join-Path $PSScriptRoot "output\chocolatey-test-environment_${Version}_${Provider}.box.sha256"
if (Test-Path $checksumFile) { Remove-Item $checksumFile -Force }

Write-Output "Building $source $Version (debug log: $env:PACKER_LOG_PATH)"
& packer @packerArgs
if ($LASTEXITCODE) { throw "packer build failed ($LASTEXITCODE)" }

Get-ChildItem output -Filter "*_${Version}_*" | Format-Table Name, @{ n = 'SizeGB'; e = { [math]::Round($_.Length / 1GB, 2) } } -AutoSize
