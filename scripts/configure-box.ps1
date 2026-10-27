# Settings applied after patching. The aim is a quiet, deterministic machine:
# verifier and local test VMs are short-lived, so nothing should start doing
# background maintenance while a package is being installed.
# Replaces set-winrm-automatic.bat, uac-disable.bat and dis-updates.bat.
$ErrorActionPreference = 'Stop'

function Set-RegistryValue($Path, $Name, $Value, $Type = 'DWord') {
  if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
  Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}

Write-Output 'Disabling automatic Windows Updates (policy)'
# The old dis-updates.bat set AUOptions under CurrentVersion\WindowsUpdate,
# which Windows 10 / Server 2016 and later ignore, and then deleted this policy
# key. The policy is what actually stops automatic scans and installs.
# The wuauserv service is left alone so KB packages (wusa.exe) keep working.
$au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
Set-RegistryValue $au NoAutoUpdate 1
Set-RegistryValue $au AUOptions 1
Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' AUOptions 1

Write-Output 'Stopping Server Manager from opening at logon'
Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\ServerManager' DoNotOpenServerManagerAtLogon 1

Write-Output 'Disabling background maintenance tasks'
$tasks = @(
  @{ Path = '\Microsoft\Windows\Server Manager\'; Name = 'ServerManager' }
  @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' }
  @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater' }
  @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' }
  @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' }
  @{ Path = '\Microsoft\Windows\Defrag\'; Name = 'ScheduledDefrag' }
  @{ Path = '\Microsoft\Windows\DiskDiagnostic\'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
  @{ Path = '\Microsoft\Windows\Chkdsk\'; Name = 'ProactiveScan' }
  @{ Path = '\Microsoft\Windows\Windows Error Reporting\'; Name = 'QueueReporting' }
)
foreach ($task in $tasks) {
  if (Get-ScheduledTask -TaskPath $task.Path -TaskName $task.Name -ErrorAction SilentlyContinue) {
    Disable-ScheduledTask -TaskPath $task.Path -TaskName $task.Name | Out-Null
    Write-Output "  disabled $($task.Path)$($task.Name)"
  }
  else {
    Write-Output "  not present: $($task.Path)$($task.Name)"
  }
}

Write-Output 'Disabling UAC'
Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' EnableLUA 0

Write-Output 'Setting WinRM to start automatically'
Set-Service -Name WinRM -StartupType Automatic
