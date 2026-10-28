# Changelog

Versions of the `chocolatey/test-environment` Vagrant box.

## Unreleased

- The Vagrantfile embedded in the box no longer sets `config.windows.halt_timeout`. Vagrant ignores that setting, so the box behaves the same.

## 3.4.0 (2026-10-27)

Windows Server 2019, built from the 17763.3650 evaluation ISO with Windows Updates through the build date. The first version built from this public repository.

The box is no longer published to the HCP Vagrant Registry, which is going offline. Build it from this repository instead. The README explains how, and how to use it with chocolatey-test-environment.

Changes since 3.3.1:

- Windows Defender is now removed from the Hyper-V box as well as the VirtualBox box.
- .NET Framework 4.8 is now patched. Previously it shipped without its cumulative updates.
- Automatic Windows Updates are turned off by policy.
- Fewer background tasks run during a test. Server Manager no longer opens at logon, scheduled maintenance tasks are turned off, and .NET assemblies are precompiled so NGEN doesn't run after boot.
- The Hyper-V box is now Generation 2 (UEFI and Secure Boot), and no longer exposes nested virtualization.
- The box is smaller, because unused disk space is cleaned up and reclaimed before packaging.

## 3.3.1 (2025-02-15)

Windows Server 2019 with WSL enabled and .NET 3.5 and 4.8 preinstalled. Windows Updates through 2025-02-14.
An updates-only refresh of 3.2.0.

## 3.2.0 (2024-06-17)

Windows Server 2019 with WSL enabled and .NET 3.5 and 4.8 preinstalled. Windows Updates through 2024-05-28.
First release with a Hyper-V box.

## 3.0.0 (2023-01-19)

First Windows Server 2019 release (VirtualBox only). WSL enabled, .NET 3.5 and 4.8 preinstalled.
Windows Updates through 2023-01-12.

## 2.0.0 (2020-12-09)

Windows Server 2012 R2 with KB2919442, KB2919355, KB2999226, KB3035131 and KB3118401.
The last 2012 R2 version.
