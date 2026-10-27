# Shrinks the image before it is packaged. Runs once patching is finished.
# Replaces compile-dotnet-assemblies.bat and the cleanup half of compact.bat.
$ErrorActionPreference = 'Stop'

# Exit codes decide success. With 'Stop' in effect, Windows PowerShell 5.1 would
# otherwise turn any stderr text from a native tool into a terminating error.
function Invoke-Native([string]$FilePath, [string[]]$Arguments, [int[]]$ValidExitCodes = @(0)) {
  $ErrorActionPreference = 'Continue'
  & $FilePath @Arguments 2>&1 | Out-Null
  if ($LASTEXITCODE -notin $ValidExitCodes) {
    throw "$FilePath $($Arguments -join ' ') exited with $LASTEXITCODE."
  }
}

# Precompile .NET assemblies now, against the patched framework, so the NGEN
# idle tasks do not burn CPU during the first minutes of every verifier VM.
Write-Output 'Precompiling .NET assemblies (ngen)'
foreach ($framework in 'Framework', 'Framework64') {
  $ngen = "$env:windir\Microsoft.NET\$framework\v4.0.30319\ngen.exe"
  Invoke-Native $ngen 'update', '/force', '/queue'
  Invoke-Native $ngen 'executequeueditems'
}

# The single biggest size win: drop superseded component versions left behind
# by cumulative updates. /ResetBase makes installed updates permanent, which is
# fine for a disposable box. The previous build never did this.
Write-Output 'Cleaning up the component store (DISM /StartComponentCleanup /ResetBase)'
Invoke-Native dism.exe '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase', '/NoRestart'

Write-Output 'Clearing the Windows Update download cache'
Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -ErrorAction SilentlyContinue
if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
  Delete-DeliveryOptimizationCache -Force
}

Write-Output 'Removing temporary files and servicing logs'
$paths = @(
  'C:\Windows\Temp\*'
  'C:\Users\*\AppData\Local\Temp\*'
  'C:\Windows\Logs\CBS\*'
  'C:\Windows\Logs\DISM\*'
  'C:\Windows\Logs\dosvc\*'
  'C:\Windows\Prefetch\*'
)
foreach ($path in $paths) {
  # Leave Packer's own uploaded scripts (packer-*) alone: Packer still needs
  # them after this script exits, and it deletes them itself.
  Get-Item $path -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike 'packer-*' } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Clearing event logs'
# Build-time noise in the logs is confusing when inspecting a failed verifier run.
# Some analytic/debug logs refuse to be cleared; skip those rather than fail.
$session = [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession
$skipped = 0
foreach ($log in $session.GetLogNames()) {
  try { $session.ClearLog($log) } catch { $skipped++ }
}
Write-Output "  cleared event logs ($skipped could not be cleared and were skipped)"

# The pagefile holds stale memory contents, which compress poorly. Have Windows
# zero it on shutdown, so the final (sysprep) shutdown leaves it all zeros:
# compaction and gzip then make it nearly free. The pagefile itself stays, so
# clones have one from their very first boot without depending on when
# setup reboots.
# The sysprep answer file (scripts/unattend.xml) turns this back off in each
# clone, so their shutdowns are not slowed down. Takes effect after the restart
# that follows this script.
Write-Output 'Zeroing the pagefile at shutdown (until first boot of each clone)'
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name ClearPageFileAtShutdown -Value 1 -Type DWord
