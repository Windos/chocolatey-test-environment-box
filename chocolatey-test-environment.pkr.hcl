# Chocolatey Test Environment - Windows Server 2019 Datacenter (Desktop Experience)
#
# Used by the Chocolatey Package Verifier / Package Scanner services and built
# as chocolatey/test-environment for local package testing. The OS deliberately
# tracks the OLDEST supported Windows Server: if a package works there it will
# generally work on newer releases.
#
#   packer init .
#   packer build -only='hyperv-iso.hyperv' -var image_version=3.4.0 .
#   packer build -only='virtualbox-iso.virtualbox' -var image_version=3.4.0 .
#
# See build.ps1, which wraps the above.

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = "1.1.5"
    }
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "1.1.5"
    }
    vagrant = {
      source  = "github.com/hashicorp/vagrant"
      version = "1.1.7"
    }
    windows-update = {
      source  = "github.com/rgl/windows-update"
      version = "0.18.5"
    }
  }
}

variable "image_version" {
  type        = string
  description = "Version stamped into the box file name."
}

variable "iso_url" {
  type        = string
  description = "Windows Server 2019 evaluation ISO (17763.3650). A local path works too."
  default     = "https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66749/17763.3650.221105-1748.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:6DAE072E7F78F4CCAB74A45341DE0D6E2D45C39BE25F1F5920A2AB4F51D7BCBB"
}

variable "hyperv_switch_name" {
  type        = string
  description = "Hyper-V switch with internet access (needed for Windows Update)."
  default     = "Default Switch"
}

variable "disk_size" {
  type    = number
  default = 76800
}

# Build-time sizing only. The box's runtime defaults (2 vCPU / 2 GB) are set in
# vagrantfile-windows_2019.template and by the consumer's Vagrantfile.
variable "build_cpus" {
  type    = number
  default = 4
}

variable "build_memory" {
  type    = number
  default = 4096
}

variable "headless" {
  type    = bool
  default = true
}

variable "output_directory" {
  type    = string
  default = "output"
}

locals {
  vm_name = "chocolatey-test-environment"

  # Delivered on a secondary CD (labelled UNATTEND) rather than a floppy, since
  # Hyper-V Gen 2 has no floppy controller. Needs oscdimg (Windows ADK
  # Deployment Tools) or xorriso on the build host's PATH.
  cd_files = [
    "./scripts/disable-screensaver.ps1",
    "./scripts/disable-winrm.ps1",
    "./scripts/enable-winrm.ps1",
  ]

  # Generalizes and powers off; see scripts/sysprep.ps1 for why it runs as a task.
  sysprep_command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\Windows\\Temp\\sysprep.ps1"
}

source "hyperv-iso" "hyperv" {
  vm_name               = local.vm_name
  generation            = 2
  configuration_version = "8.0" # importable on Hyper-V 2016 / Windows 10 1607 and later
  enable_secure_boot    = true
  secure_boot_template  = "MicrosoftWindows"
  enable_dynamic_memory = false
  cpus                  = var.build_cpus
  memory                = var.build_memory
  disk_size             = var.disk_size
  # 1 MB blocks instead of the 32 MB default: freed space is reclaimed at a
  # much finer grain when the VHDX is compacted, so the box is smaller.
  disk_block_size = 1
  switch_name     = var.hyperv_switch_name
  headless        = var.headless

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum
  cd_label     = "UNATTEND"
  cd_files     = local.cd_files
  cd_content = {
    "Autounattend.xml" = templatefile("${path.root}/answer_files/2019_choco/Autounattend.xml.pkrtpl", { firmware = "uefi" })
  }

  # Gen 2 shows "Press any key to boot from CD or DVD"; keep pressing until it takes.
  first_boot_device = "DVD"
  boot_wait         = "1s"
  boot_command      = ["<spacebar><wait1><spacebar><wait1><spacebar><wait1><spacebar><wait1><spacebar><wait1><spacebar>"]

  communicator     = "winrm"
  winrm_username   = "vagrant"
  winrm_password   = "vagrant"
  winrm_timeout    = "2h"
  shutdown_command = local.sysprep_command
  shutdown_timeout = "30m"
}

source "virtualbox-iso" "virtualbox" {
  vm_name       = local.vm_name
  guest_os_type = "Windows2019_64"
  firmware      = "bios"
  cpus          = var.build_cpus
  memory        = var.build_memory
  disk_size     = var.disk_size
  headless      = var.headless

  # Deliberately NOT using hard_drive_discard (TRIM): with VirtualBox running on
  # top of Hyper-V (NEM mode) the guest's first TRIM wedges the disk I/O queue
  # and Windows hangs on the boot spinner. The setting is also exported into
  # the box, so users on Hyper-V-enabled hosts would hit it too. Free space is
  # zeroed instead (scripts/optimize-disk.ps1); export skips zero blocks.
  hard_drive_interface = "sata"
  iso_interface        = "sata"

  gfx_controller = "vboxsvga"
  gfx_vram_size  = 128

  # Attach the Guest Additions ISO bundled with the host's VirtualBox, so the
  # additions always match the VirtualBox version used to build.
  guest_additions_mode      = "attach"
  guest_additions_interface = "sata"

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum
  cd_label     = "UNATTEND"
  cd_files     = local.cd_files
  cd_content = {
    "Autounattend.xml" = templatefile("${path.root}/answer_files/2019_choco/Autounattend.xml.pkrtpl", { firmware = "bios" })
  }

  boot_wait = "5s"

  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--pae", "off"],
    ["modifyvm", "{{.Name}}", "--mouse", "usbtablet"],
    ["modifyvm", "{{.Name}}", "--vrde", "off"],
    ["modifyvm", "{{.Name}}", "--rtcuseutc", "off"],
  ]

  communicator     = "winrm"
  winrm_username   = "vagrant"
  winrm_password   = "vagrant"
  winrm_timeout    = "2h"
  shutdown_command = local.sysprep_command
  shutdown_timeout = "30m"
}

build {
  sources = [
    "source.hyperv-iso.hyperv",
    "source.virtualbox-iso.virtualbox",
  ]

  provisioner "windows-shell" {
    scripts = ["./scripts/enable-rdp.bat"]
  }

  # Everything that changes the OS's component set happens BEFORE patching, so
  # Windows Update then services all of it (.NET 3.5 and 4.8 included).
  # Elevated because Windows Update / Features on Demand refuse a WinRM
  # network logon token.
  provisioner "powershell" {
    elevated_user     = "vagrant"
    elevated_password = "vagrant"
    scripts = [
      "./scripts/microsoft-updates.ps1",
      "./scripts/enable-opensshserver.ps1",
      "./scripts/install-dotnet35.ps1",
      "./scripts/install-dotnet4.8.ps1",
      "./scripts/enable-wsl.ps1",
      "./scripts/remove-defender.ps1",
      "./scripts/vm-guest-tools.ps1",
    ]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # Latest released (non-preview) cumulative updates, looping until none remain.
  provisioner "windows-update" {
    search_criteria = "IsInstalled=0 and Type='Software' and IsHidden=0 and BrowseOnly=0"
    filters = [
      "exclude:$_.Title -like '*Preview*'",
      "include:$true",
    ]
    update_limit = 50
  }

  provisioner "powershell" {
    elevated_user     = "vagrant"
    elevated_password = "vagrant"
    scripts = [
      "./scripts/configure-box.ps1",
      "./scripts/cleanup.ps1",
    ]
  }

  # Answer file for the post-sysprep boot of every clone, and the script that
  # runs sysprep (see local.sysprep_command).
  provisioner "file" {
    source      = "./scripts/unattend.xml"
    destination = "C:/Windows/Temp/unattend.xml"
  }

  provisioner "file" {
    source      = "./scripts/sysprep.ps1"
    destination = "C:/Windows/Temp/sysprep.ps1"
  }

  # Restart so DISM finishes any pending work and the pagefile-zeroing setting
  # takes effect, before free space is trimmed.
  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    elevated_user     = "vagrant"
    elevated_password = "vagrant"
    scripts           = ["./scripts/optimize-disk.ps1"]
  }

  post-processors {
    post-processor "vagrant" {
      output               = "${var.output_directory}/chocolatey-test-environment_${var.image_version}_{{.Provider}}.box"
      vagrantfile_template = "${path.root}/vagrantfile-windows_2019.template"
      architecture         = "amd64"
      compression_level    = 9
      keep_input_artifact  = false
    }
    post-processor "checksum" {
      checksum_types = ["sha256"]
      output         = "${var.output_directory}/chocolatey-test-environment_${var.image_version}_{{.BuildName}}.box.{{.ChecksumType}}"
    }
  }
}
