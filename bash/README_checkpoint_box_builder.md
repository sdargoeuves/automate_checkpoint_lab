# Check Point R81.20 Vagrant Box Builder

This document explains what `checkpoint_box_builder.sh` does and how to use it to build a reusable Check Point R81.20 Vagrant box for the lab.

It automates three phases:

- Prepare a VM disk and cloud-init style ISO with your IP/hostname.
- Boot the VM once so it runs First Time Wizard and self-configures.
- Package the resulting VM disk as a `vagrant-libvirt` box with metadata.

---

## Requirements

On the build host you need:

- A Check Point R81.20 qcow2 disk image (for example `cp_r81_20_disk.qcow2`).
- `libvirt` and `qemu-kvm`.
- `virt-install`, `virsh`.
- `qemu-img` (for disk resize/copy).
- `genisoimage` (for the cloud-init ISO).
- `expect` (only required for `auto` mode).
- `vagrant` and the `vagrant-libvirt` provider to consume the box.

The script assumes you run it from inside the repo and that it may create temporary files under:

- `_tmp_cp_box/` – working directory with disks and box build files.
- `checkpoint_box_builder.log` – high-level log.
- `checkpoint_box_builder.console.log` – console output from the initial VM boot (auto mode).

---

## High-level workflow

The script implements three subcommands:

- `prepare` – clone and resize the original disk, generate cloud-init ISO, and optionally start the VM.
- `build` – package a configured disk into a `vagrant-libvirt` box.
- `auto` – run `prepare`, wait for first boot to finish, shut down and clean up the VM, then run `build`.

Usage:

```bash
./checkpoint_box_builder.sh help
./checkpoint_box_builder.sh prepare --disk ../cp_r81_20_disk.qcow2
./checkpoint_box_builder.sh build
./checkpoint_box_builder.sh auto --disk ../cp_r81_20_disk.qcow2
```

---

## `prepare`: build configured disk + ISO

Command:

```bash
.checkpoint_box_builder.sh prepare [--disk PATH] [--auto-build]
```

What it does:

- Validates the original qcow2 disk (default `../cp_r81_20_disk.qcow2`).
- Interactively asks for:
  - Vagrant box base name (defaults to `checkpoint-r8120`).
  - Box version (`81.20` by default).
  - Hostname for the VM (default `checkpoint-gw`).
  - IP address (default `10.194.58.200`).
  - Netmask (default `255.255.255.0`).
  - Default gateway (auto-derived from the IP, `<ip>.1`).
- Writes a `cloud-config` style `user_data` file to:
  - Set hostname and local admin password (`admin123` in this lab script).
  - Configure the management IP, mask, and gateway on `eth0`.
  - Run the First Time Wizard (`config_system`) in standalone mode (gateway + management).
  - Set the expert password non-interactively (`admin123` here).
  - Create a `vagrant` user with:
    - Local home directory `/home/vagrant`.
    - Admin role and `/bin/bash` shell.
    - Password `vagrant`.
    - Insecure Vagrant SSH public key in `~vagrant/.ssh/authorized_keys`.
    - Passwordless sudo in `/etc/sudoers`.
  - Enable DHCP client on `eth0` (in addition to the static IP) and save config.
  - Configure the Management API via `mgmt_cli`:
    - Retry login several times.
    - Set `api-settings` to accept API calls from “All IP addresses that can be used for GUI clients”.
    - Publish changes.
- Generates a cloud-init ISO under the script directory:
  - `cp_r81_20_config_<ip_with_underscores>.iso`.
- Copies the original disk into `_tmp_cp_box/` and resizes it to 100G:
  - `cp_disk_<ip_with_underscores>.qcow2`.
- Stores the chosen box name and version in `_tmp_cp_box/.box_name` and `_tmp_cp_box/.box_version` for later use.
- Prints a ready-to-run `virt-install` command that:
  - Attaches the resized disk as IDE.
  - Attaches the generated ISO as a read-only CDROM.
  - Uses the default libvirt network (`network:default`).
  - Creates a text-based console.

If you confirm, `prepare` can also:

- Start the VM immediately with `virt-install`.
- In `--auto-build` mode, wrap `virt-install` in an `expect` script that:
  - Logs console output to `checkpoint_box_builder.console.log`.
  - Watches for the `login:` prompt indicating first boot completed.
  - Exits the console cleanly when the login prompt appears.

After the VM exits, you shut it down (or `auto` mode does this via `virsh shutdown`) and move on to `build`.

---

## `build`: package the Vagrant box

Command:

```bash
.checkpoint_box_builder.sh build [--disk PATH]
```

What it does:

- Locates the configured qcow2 disk:
  - Either the one passed via `--disk`, or
  - The first `cp_disk_*.qcow2` in `_tmp_cp_box/` (with an interactive chooser if there are multiple).
- Reads `_tmp_cp_box/.box_name` and `_tmp_cp_box/.box_version` if present; falls back to defaults otherwise.
- Extracts the IP from the disk filename to incorporate it into the output box name.
- Creates a box build directory `_tmp_cp_box/box_build` containing:
  - `box.img` – the configured qcow2 disk.
  - `metadata.json` – provider metadata for `libvirt` with virtual size = 100 GB.
  - `Vagrantfile` – configures:
    - `libvirt` provider with KVM.
    - 8 GB RAM, 2 vCPUs.
    - SSH communicator.
    - `vagrant`/`vagrant` credentials, no key insertion.
    - Disables synced folders and fstab/hosts modification.
    - Forces guest type `redhat` to avoid auto-detection issues.
- Packs the box into a single tarball next to the script:
  - `<box_base_name>_<ip_with_underscores>.box`.
- Generates a versioned metadata file in the same directory:
  - `<box_base_name>_<ip_with_underscores>_metadata.json`.
  - Describes the box, IP address, version, provider, and local file URL.
- Optionally cleans up `_tmp_cp_box/` (automatic in `auto` mode, interactive in manual `build`).

Example of adding the box to Vagrant using the metadata file:

```bash
vagrant box add checkpoint-r8120_10_194_58_200_metadata.json
```

Or, without metadata:

```bash
vagrant box add checkpoint-r8120 checkpoint-r8120_10_194_58_200.box
```

---

## `auto`: fully automated flow

Command:

```bash
.checkpoint_box_builder.sh auto [--disk PATH]
```

What it does:

- Explains the steps, then prompts for confirmation.
- Calls `prepare --auto-build` with the remaining arguments:
  - Runs the same interactive prompts for box name, version, hostname, and network.
  - Generates the ISO and resized qcow2 disk.
  - Starts the VM via `virt-install` wrapped in `expect`.
- When the `login:` prompt appears:
  - Exits the console.
  - Gracefully shuts down the VM with `virsh shutdown`.
  - Waits for the domain state to become `shut off`.
  - Destroys/undefines the libvirt domain to keep the environment clean.
- Calls `build --disk <prepared_disk> --auto-mode`:
  - Skips interactive confirmations.
  - Always cleans up `_tmp_cp_box/` at the end.

The result is a ready-to-use Check Point R81.20 Vagrant box based on your chosen IP/hostname and a consistent first-boot configuration suitable for the Ansible playbooks available in this repo.

