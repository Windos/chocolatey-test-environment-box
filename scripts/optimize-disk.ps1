# Final pass before sysprep: make free space cheap to store, so the exported box
# only contains blocks that are actually in use. Replaces UltraDefrag (from
# SourceForge) and SDelete (from a third-party Azure blob).
#
# Hyper-V: the Gen 2 SCSI disk passes TRIM through, so a retrim releases free
#   space from the VHDX directly and Packer's compaction reclaims it.
#   Previously the Hyper-V build skipped this step entirely.
# VirtualBox: TRIM is deliberately not enabled (it can hang the guest's disk
#   I/O; see the template), so free space is overwritten with zeros instead.
#   VirtualBox's export skips all-zero blocks.
$ErrorActionPreference = 'Stop'

switch -Wildcard ($env:PACKER_BUILDER_TYPE) {
  'virtualbox*' {
    # Leave a little headroom so Windows never actually runs out of space.
    $reserve = 512MB
    $drive = [IO.DriveInfo]'C'
    $toWrite = $drive.AvailableFreeSpace - $reserve
    $path = 'C:\zero-fill.tmp'
    Write-Output ('Zeroing {0:N1} GB of free space on C:' -f ($toWrite / 1GB))

    $chunk = 64MB
    $buffer = New-Object byte[] $chunk
    $stream = [IO.File]::Open($path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
      $written = [long]0
      while ($written -lt $toWrite) {
        $count = [int][Math]::Min([long]$chunk, $toWrite - $written)
        $stream.Write($buffer, 0, $count)
        $written += $count
      }
      $stream.Flush($true)
    }
    finally {
      $stream.Dispose()
      Remove-Item $path -Force -ErrorAction SilentlyContinue
    }
    Write-Output ('Wrote {0:N1} GB of zeros' -f ($written / 1GB))
  }
  default {
    Write-Output 'Defragmenting C: (consolidates free space into whole blocks)'
    Optimize-Volume -DriveLetter C -Defrag -Verbose

    Write-Output 'Retrimming C: (releases free blocks to the virtual disk)'
    Optimize-Volume -DriveLetter C -ReTrim -Verbose
  }
}

$volume = Get-Volume -DriveLetter C
Write-Output ('C: used {0:N2} GB, free {1:N2} GB' -f (($volume.Size - $volume.SizeRemaining) / 1GB), ($volume.SizeRemaining / 1GB))
