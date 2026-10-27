# Chocolatey Test Environment Vagrant Box

Packer templates that build the **`chocolatey/test-environment`** Vagrant box: the
Windows Server 2019 machine that the [Chocolatey Community Repository](https://community.chocolatey.org)
tests packages on.

The box is used in three places, and all of them build it from this repository:

| Consumer | Who builds the box |
|---|---|
| [Package Verifier](https://docs.chocolatey.org/en-us/community-repository/moderation/package-verifier) service | Chocolatey Software |
| [Package Scanner](https://docs.chocolatey.org/en-us/community-repository/moderation/package-scanner) service | Chocolatey Software |
| Package maintainers testing locally with [chocolatey-test-environment](https://github.com/chocolatey-community/chocolatey-test-environment) | You (see [Building](#building) and [Using the Box](#using-the-box-with-the-chocolatey-testing-environment)) |

Chocolatey Software doesn't host a prebuilt box, because Microsoft's license
terms for Windows Server don't allow it to be redistributed (see
[Evaluation Licensing](#evaluation-licensing)).

Because the community tests against it locally *and* the verifier runs against it,
the box needs to behave the same everywhere. Changes to what is installed in it
change package verification results. One difference can't be avoided: the build
installs the Windows Updates available on the day it runs, so a box you build may
be patched more recently than the one the Package Verifier is using.

## What Is in the Box

- **Windows Server 2019 Datacenter Evaluation** (Desktop Experience), en-US, UTC
- All released (non-preview) Windows and Microsoft Updates as of the build date
- .NET Framework 3.5 and 4.8, both patched
- Windows Subsystem for Linux (WSL 1) enabled
- OpenSSH Server, RDP and WinRM enabled
- User `vagrant` / password `vagrant` (administrator, auto-logon, UAC off)
- **No** Windows Defender, and automatic Windows Updates disabled by policy
- VirtualBox Guest Additions (VirtualBox box) / in-box integration services (Hyper-V box)

> [!WARNING]
> The box is deliberately insecure so that tests run without interruption: the
> credentials are well known, UAC and Windows Defender are off, and WinRM accepts
> unencrypted Basic authentication. Use it only for disposable test VMs. Vagrant
> binds forwarded ports (RDP, WinRM, SSH) to every network interface on the host
> unless `host_ip` is set, so on a network you don't trust, add
> `host_ip: "127.0.0.1"` to the forwarded ports in your `Vagrantfile`.

### Why Windows Server 2019

The box deliberately runs the **oldest supported** Windows Server release. If a
package works there, it will generally work on newer versions. Packages that
genuinely need a newer OS are documented and exempted from testing.

Moving to a newer Windows Server is a product decision rather than a maintenance
task, and should be a major version bump (for example 3.x → 4.0.0). Server 2019
extended support ends **9 January 2029**.

### Evaluation Licensing

This repository contains no Microsoft software. The build downloads Microsoft's
Windows Server 2019 evaluation media, and the answer file accepts Microsoft's
license terms for it on your behalf (`AcceptEula`). Read those terms before you
build; `winver` in a built VM links to them.

Those terms are also why there is no prebuilt box to download. A box is an
installed copy of Windows, and the license says that you "may not distribute
instances to third parties" (section 3.g), and may not "publish, rent, lease,
lend, or copy the software" (section 3.h). So everyone, Chocolatey Software
included, builds their own box from this repository.

The box is built from Microsoft's free evaluation media and is generalized with
sysprep, so every `vagrant up` starts a fresh evaluation period. The box itself
never expires. A VM that can reach the internet activates the 180-day evaluation
automatically; one that cannot gets a 10-day grace period. Either is far longer
than a verifier run.

## Versioning

| Change | Bump | Example |
|---|---|---|
| Windows Updates refresh only, no build changes | patch | 3.3.0 → 3.3.1 |
| Build or content changes on the same OS | minor | 3.3.1 → 3.4.0 |
| Different Windows version | major | 3.x → 4.0.0 |

See [CHANGELOG.md](CHANGELOG.md) for what changed in each box version.

## Building

### Requirements

| Tool | Tested version | Install |
|---|---|---|
| Packer | 1.16.0 | `choco install packer` |
| Windows ADK *Deployment Tools* (for `oscdimg.exe`) | 10.1.26100 | See below |
| Hyper-V (for the Hyper-V box) | Windows 11 host | `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All` |
| VirtualBox (for the VirtualBox box) | 7.2.x | `choco install virtualbox` |
| Vagrant (to test the result) | 2.4.9 | `choco install vagrant` |

The Packer plugins are pinned in `chocolatey-test-environment.pkr.hcl`, and
`packer init` (run by `build.ps1`) downloads them.

**oscdimg:** the answer file is delivered on a small generated CD, because
Hyper-V Gen 2 VMs have no floppy drive. Packer needs `oscdimg.exe` (or
`xorriso`) to make it. The `windows-adk` Chocolatey package installs the entire
ADK. Installing just the Deployment Tools feature is enough:

```powershell
Invoke-WebRequest https://go.microsoft.com/fwlink/?linkid=2289980 -OutFile adksetup.exe
.\adksetup.exe /features OptionId.DeploymentTools /quiet /norestart /ceip off
```

`build.ps1` finds oscdimg in the default ADK location, so there's no need to add it to `PATH`.

Disk space: allow about **60 GB** free per build, for the VM, the exported artifact and the box.

`build.ps1` and these instructions assume a Windows host, which is the only kind
the build is tested on. On another x86-64 host with VirtualBox, you can try
running Packer directly, using the `packer` commands at the top of
`chocolatey-test-environment.pkr.hcl`, with `xorriso` installed in place of
oscdimg. This is untested.

### The ISO

The template defaults to Microsoft's public evaluation download of Windows Server
2019 build 17763.3650 and verifies its SHA-256. Packer caches the download in
`packer_cache/`. To reuse a copy you already have, pass it with `-IsoUrl`.

| | |
|---|---|
| File | `17763.3650.221105-1748.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso` |
| SHA-256 | `6DAE072E7F78F4CCAB74A45341DE0D6E2D45C39BE25F1F5920A2AB4F51D7BCBB` |
| Source | [Windows Server 2019 Evaluation Center](https://www.microsoft.com/en-us/evalcenter/download-windows-server-2019) |

The answer file installs the image named `Windows Server 2019 SERVERDATACENTER`,
which is index 4 on this ISO. Check this again if you switch to different media.

### Hyper-V and VirtualBox on the Same Host

When the Windows hypervisor is running, VirtualBox runs on top of it through the
Windows Hypervisor Platform ("NEM" mode, shown as `Attempting fall back to NEM`
in the VM's `VBox.log`). This is slower, but it works and produces the same box.
It's the practical choice on most modern Windows hosts. Install the
**Windows Hypervisor Platform** optional feature (`HypervisorPlatform`) for it.

To build the VirtualBox box natively instead, the hypervisor must not load at all:

1. Build the **Hyper-V box** first, with the hypervisor on.
2. Run `bcdedit /set hypervisorlaunchtype off` and reboot.
3. Check `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent` is `False`.
   If it is still `True`, **virtualization-based security** is launching the
   hypervisor regardless of the boot setting. The `Microsoft-Windows-DeviceGuard/Operational`
   event log (event 153) says which VBS policies are active. The usual sources
   are Memory integrity (Core isolation), Credential Guard, and Windows Hello
   enhanced sign-in security. These are security features of your machine, so
   decide carefully before turning them off, and turn them back on afterwards.
4. Build the **VirtualBox box**.
5. Run `bcdedit /set hypervisorlaunchtype auto`, restore anything you turned off, and reboot.

`build.ps1` checks the hypervisor state. It warns for VirtualBox, and it stops
the Hyper-V build if the hypervisor isn't running.

### Run the Build

From an **elevated** PowerShell prompt:

```powershell
git clone https://github.com/chocolatey-community/chocolatey-test-environment-box
cd chocolatey-test-environment-box

.\build.ps1 -Provider hyperv -Version 3.4.0
.\build.ps1 -Provider virtualbox -Version 3.4.0

# Reuse a local ISO rather than downloading it
.\build.ps1 -Provider hyperv -Version 3.4.0 -IsoUrl D:\ISOs\17763.3650.221105-1748.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso

# Show the VM console while building (useful when debugging)
.\build.ps1 -Provider hyperv -Version 3.4.0 -ShowWindow
```

`-Version` only names the output files. Use the box version from
[CHANGELOG.md](CHANGELOG.md) for the source you're building.

Hyper-V builds use the `Default Switch`. Pass `-HyperVSwitchName` to use
another switch; it needs internet access for Windows Update.

Each build takes roughly 1.5–3 hours, most of it Windows Update. The results land in `output/`:

```
output/chocolatey-test-environment_3.4.0_hyperv.box
output/chocolatey-test-environment_3.4.0_hyperv.box.sha256
output/chocolatey-test-environment_3.4.0_virtualbox.box
output/chocolatey-test-environment_3.4.0_virtualbox.box.sha256
```

Packer's debug log for each run is written to `logs/`.

### What the Build Does

1. Boots Windows Setup from the ISO, with `Autounattend.xml` rendered from
   `answer_files/2019_choco/Autounattend.xml.pkrtpl` onto a second CD. The Hyper-V
   box uses a GPT/UEFI disk layout (Gen 2) and the VirtualBox box uses MBR/BIOS.
2. On first logon, enables WinRM so Packer can connect.
3. Installs everything that changes the OS component set *before* patching:
   Microsoft Update opt-in, OpenSSH Server, .NET 3.5 (from the ISO), .NET 4.8,
   WSL, Defender removal, and guest tools.
4. Applies Windows Updates with [rgl/packer-plugin-windows-update](https://github.com/rgl/packer-plugin-windows-update),
   rebooting and repeating until none are left.
5. `configure-box.ps1`: disables automatic updates (policy), Server Manager at
   logon, and background maintenance tasks. Disables UAC.
6. `cleanup.ps1`: precompiles .NET assemblies, runs DISM component cleanup with
   `/ResetBase`, deletes caches, temp files and event logs, and sets the pagefile to be
   zeroed at shutdown (so the final shutdown leaves it compressible).
7. `optimize-disk.ps1`: on Hyper-V, defragments and retrims so freed space is returned to
   the VHDX. On VirtualBox, overwrites free space with zeros, which the export skips.
   TRIM is deliberately left off there, because it can hang the guest under NEM.
8. `scripts/sysprep.ps1` runs `sysprep /generalize /oobe /shutdown` from a
   SYSTEM scheduled task, because generalize removes the network adapter and
   would otherwise kill a sysprep started over WinRM. It deliberately doesn't
   use `/mode:vm`, which skips the reboot that completes each clone's new
   computer name and slows every logon enough to break SSH-based Vagrant. On
   each clone's first boot, `scripts/unattend.xml` turns pagefile zeroing back
   off and removes the task and the uploaded files.
9. The Vagrant post-processor packages the box (gzip level 9, `amd64`), and a checksum file is written.

## Using the Box With the Chocolatey Testing Environment

The `Vagrantfile` in [chocolatey-test-environment](https://github.com/chocolatey-community/chocolatey-test-environment)
uses a box named `chocolatey/test-environment`. Add the box you built under that
name and the `Vagrantfile` works unchanged:

```powershell
# Remove any copy previously downloaded from the HCP Vagrant Registry, so it isn't used instead.
# It's fine if this reports that there is no such box.
vagrant box remove chocolatey/test-environment --all --provider virtualbox

vagrant box add --name chocolatey/test-environment output\chocolatey-test-environment_3.4.0_virtualbox.box --provider virtualbox
```

For Hyper-V, use `--provider hyperv` and the `_hyperv.box` file. Then carry on
from `vagrant up` in the chocolatey-test-environment instructions.

A box added from a file has no version, so `vagrant box outdated` and
`vagrant box update` don't work for it, and a `config.vm.box_version` constraint
won't match it. To move to a newer box, build it, `vagrant destroy` your test
environment, then remove the old box and add the new one as above.

## Testing a Box Locally

```powershell
vagrant box add --name choco-test-local output\chocolatey-test-environment_3.4.0_hyperv.box --provider hyperv
git clone https://github.com/chocolatey-community/chocolatey-test-environment
cd chocolatey-test-environment
# In the Vagrantfile, set: config.vm.box = "choco-test-local"
vagrant up --provider hyperv
vagrant destroy -f
vagrant box remove choco-test-local
```

Things worth checking before a release:

- `vagrant up` reaches WinRM without intervention, and the provisioners run.
- `choco install` works (for example `choco install -y 7zip`).
- In the guest: `Get-HotFix | Sort InstalledOn | Select -Last 3` shows the expected
  cumulative update; `(Get-WindowsFeature Windows-Defender).InstallState` is `Available`,
  not `Installed`; .NET 4.8 release key is `528049`.
- The box is not unexpectedly larger than the previous version.

## Releasing

Nothing in this repository publishes anything, and no prebuilt box is published.
Releases are recorded in [CHANGELOG.md](CHANGELOG.md) and tagged in this
repository. Chocolatey Software builds the Package Verifier and Package Scanner
box from the released source, the same way anyone else does, and records the
"Windows Updates through" date of that build in the changelog.

## Contributing

Issues and pull requests are welcome. Anything that changes what is installed in
the box, or how it is configured, changes Package Verifier results for every
package. Please open an issue to discuss a change like that before starting a
pull request.

## Repository Layout

```
chocolatey-test-environment.pkr.hcl      Packer template (Hyper-V + VirtualBox)
build.ps1                                Build wrapper: preflight checks, init, validate, build
vagrantfile-windows_2019.template        Default Vagrantfile embedded in the box
answer_files/2019_choco/
  Autounattend.xml.pkrtpl                Windows Setup answer file (BIOS / UEFI variants)
scripts/
  disable-winrm.ps1                      Keeps WinRM off during Setup   (on the answer-file CD)
  enable-winrm.ps1                       Opens WinRM for Packer/Vagrant (on the answer-file CD)
  disable-screensaver.ps1                                               (on the answer-file CD)
  enable-rdp.bat, enable-opensshserver.ps1, enable-wsl.ps1
  microsoft-updates.ps1                  Opt in to Microsoft Update
  install-dotnet35.ps1, install-dotnet4.8.ps1
  remove-defender.ps1
  vm-guest-tools.ps1                     VirtualBox Guest Additions
  configure-box.ps1, cleanup.ps1, optimize-disk.ps1
  sysprep.ps1                            Generalizes and powers off (Packer's shutdown command)
  unattend.xml                           Answer file used by sysprep for each clone's first boot
```

## History

This repository started as a fork of
[StefanScherer/packer-windows](https://github.com/StefanScherer/packer-windows)
(itself derived from joefitzgerald/packer-windows). Everything unrelated to
this box has since been removed. `scripts/install-dotnet35.ps1` comes from
[gildas/packer-windows](https://github.com/gildas/packer-windows).

This repository is licensed under the [Apache License, Version 2.0](LICENSE).
The license and copyright notices of the projects it draws on are in [NOTICE](NOTICE).
