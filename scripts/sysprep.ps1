# Packer's shutdown_command: generalize the image and power off.
#
# Sysprep is started as a SYSTEM scheduled task instead of directly, because
# the generalize pass removes the network adapter. That drops the WinRM
# session Packer ran this from, and Windows then terminates the session's
# processes: sysprep started directly is killed partway through generalize,
# leaving the VM running and the build waiting forever. The task runs outside
# the WinRM session, and Packer just waits for the VM to power off.
#
# The task is deleted again when each clone first boots (scripts/unattend.xml).
#
# Deliberately NOT using /mode:vm. It skips the reboot after the specialize
# pass, which leaves every clone half-renamed: the TCP/IP hostname is still
# the build VM's while the new name is pending. Local logons then take ~20 s
# (Windows looks the old name up as if it were a remote domain), long enough
# that sshd's per-connection user lookup outlives Vagrant's SSH timeout, so
# the Package Verifier's `winssh` communicator could not connect for ~30 min.
$ErrorActionPreference = 'Stop'

$action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\Sysprep\sysprep.exe' `
  -Argument '/generalize /oobe /shutdown /quiet /unattend:C:\Windows\Temp\unattend.xml'
Register-ScheduledTask -TaskName 'Packer Sysprep' -Action $action -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName 'Packer Sysprep'
Write-Output 'Sysprep started; the VM will power off when it finishes.'
