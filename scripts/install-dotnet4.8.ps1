# Installs .NET Framework 4.8 (Server 2019 ships with 4.7.2).
# Runs BEFORE Windows Update so the 4.8 cumulative updates are applied on top;
# previously it ran after patching and the box shipped an unpatched 4.8.
# 4.8.1 is not an option: it does not support Server 2019 / build 17763.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$release = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Release
if ($release -ge 528040) {
  Write-Output ".NET Framework 4.8 or later already installed (release $release)."
  exit 0
}

$url = 'https://download.visualstudio.microsoft.com/download/pr/2d6bb6b2-226a-4baa-bdec-798822606ff1/8494001c276a4b96804cde7829c04d7f/ndp48-x86-x64-allos-enu.exe'
$installer = 'C:\Windows\Temp\ndp48-x86-x64-allos-enu.exe'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing

$signature = Get-AuthenticodeSignature $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
  throw "Refusing to run $installer - signature status '$($signature.Status)', signer '$($signature.SignerCertificate.Subject)'."
}

Write-Output 'Installing .NET Framework 4.8...'
$process = Start-Process -FilePath $installer -ArgumentList '/q', '/norestart' -Wait -PassThru
Remove-Item $installer -Force

# 3010 = success, reboot required. The template restarts after this block.
if ($process.ExitCode -notin 0, 3010) {
  throw ".NET Framework 4.8 installer exited with $($process.ExitCode)."
}
Write-Output ".NET Framework 4.8 installed (exit code $($process.ExitCode))."
