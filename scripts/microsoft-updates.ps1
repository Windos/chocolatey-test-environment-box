# Opt in to Microsoft Update (not just Windows Update) so the windows-update
# provisioner also patches other Microsoft products such as .NET Framework.
# Replaces microsoft-updates.bat, which wrote a temporary VBScript to a:\.
$ErrorActionPreference = 'Stop'

$au = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update'
New-Item -Path $au -Force | Out-Null
Set-ItemProperty -Path $au -Name EnableFeaturedSoftware -Value 1 -Type DWord
Set-ItemProperty -Path $au -Name IncludeRecommendedUpdates -Value 1 -Type DWord

# 7 = allow pending + online registration, and register the service with AU.
$serviceManager = New-Object -ComObject Microsoft.Update.ServiceManager
$null = $serviceManager.AddService2('7971f918-a847-4430-9279-4a52d1efe18d', 7, '')
Write-Output 'Microsoft Update service registered.'
