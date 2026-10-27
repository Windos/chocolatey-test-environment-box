# Removes Windows Defender from the box, on every provider.
#
# Previously this happened only in the VirtualBox build (via debloat-windows.ps1,
# which pulled scripts from an unpinned GitHub master branch), so the Hyper-V box
# still had Defender. Real-time scanning slows package installs considerably and
# can quarantine package payloads mid-test, which makes verifier results noisy.
#
# Done before Windows Update so no definition/platform updates are downloaded.
$ErrorActionPreference = 'Stop'

$feature = Get-WindowsFeature -Name Windows-Defender
if ($feature.InstallState -eq 'Installed') {
  $result = Uninstall-WindowsFeature -Name Windows-Defender
  Write-Output "Windows Defender removed. Restart needed: $($result.RestartNeeded)"
}
else {
  Write-Output "Windows Defender not installed (state: $($feature.InstallState))."
}
