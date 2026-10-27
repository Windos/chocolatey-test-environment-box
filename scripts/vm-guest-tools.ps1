# Installs hypervisor guest tools.
#
# VirtualBox: Packer attaches the Guest Additions ISO that ships with the host's
# VirtualBox (guest_additions_mode = "attach"), so the additions always match
# the VirtualBox version used for the build. This replaces scraping
# download.virtualbox.org for the "latest" version and installing 7-Zip 19.00
# to unpack it.
#
# Hyper-V: Server 2019 has the integration services in-box; nothing to do.
$ErrorActionPreference = 'Stop'

switch -Wildcard ($env:PACKER_BUILDER_TYPE) {
  'virtualbox*' {
    $drive = Get-PSDrive -PSProvider FileSystem |
      Where-Object { Test-Path (Join-Path $_.Root 'VBoxWindowsAdditions.exe') } |
      Select-Object -First 1
    if (-not $drive) {
      throw 'VirtualBox Guest Additions ISO not found on any drive. Is guest_additions_mode set to "attach"?'
    }
    $root = $drive.Root
    Write-Output "Installing VirtualBox Guest Additions from $root"

    # Trust the Oracle driver-signing certificates first, otherwise the silent
    # install stops at a "Would you like to install this device software?" prompt.
    $certUtil = Join-Path $root 'cert\VBoxCertUtil.exe'
    Get-ChildItem (Join-Path $root 'cert') -Filter 'vbox*.cer' | ForEach-Object {
      # 'Continue' so informational stderr output isn't fatal; the exit code decides.
      $ErrorActionPreference = 'Continue'
      & $certUtil add-trusted-publisher $_.FullName --root $_.FullName 2>&1 | Write-Output
      $ErrorActionPreference = 'Stop'
      if ($LASTEXITCODE -ne 0) { throw "VBoxCertUtil failed for $($_.Name) with exit code $LASTEXITCODE." }
    }

    $process = Start-Process -FilePath (Join-Path $root 'VBoxWindowsAdditions.exe') -ArgumentList '/S' -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) {
      throw "VBoxWindowsAdditions.exe exited with $($process.ExitCode)."
    }
    Write-Output "VirtualBox Guest Additions installed (exit code $($process.ExitCode))."
  }
  'hyperv*' {
    Write-Output 'Hyper-V integration services are built in to Server 2019; nothing to install.'
  }
  default {
    Write-Output "No guest tools step for builder '$env:PACKER_BUILDER_TYPE'."
  }
}
