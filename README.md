# Check Point R81.20 Lab Automation

This directory contains everything needed to spin up and automate a Check Point R81.20 gateway for the lab: a Vagrant box builder and Ansible playbooks.

---

## Components

- `checkpoint_box_builder.sh` – converts an official R81.20 qcow2 image into a reusable `vagrant-libvirt` box with:
  - Fixed management IP/hostname.
  - First Time Wizard preconfigured (standalone gateway + management).
  - Local admin + expert passwords for lab use.
  - A `vagrant` user (SSH key + sudo) for automation.
- `checkpoint_configuration.yml` – base configuration playbook:
  - Locks the DB, sets hostname, configures interfaces/MTU, enables LLDP and OSPF, then saves the configuration.
- `checkpoint_firewall_rules.yml` – policy playbook:
  - Talks to the Management API, (optionally) renames the gateway object, creates network/host/group/multicast/service objects, adds rules, installs policy, and logs out.
- `vars_checkpoint.yml` – all variables for both playbooks:
  - Interfaces, LLDP/OSPF parameters, objects, firewall rules, and credentials.

For detailed explanations:

- Box builder: `playbooks/checkpoint/checkpoint_box_builder.md`
- Playbooks: `playbooks/checkpoint/checkpoint.md`

---

## Build the Check Point Vagrant box

From the repo root, with an R81.20 qcow2 image available (for example `cp_r81_20_disk.qcow2`):

```bash
./playbooks/checkpoint/checkpoint_box_builder.sh auto --disk ../cp_r81_20_disk.qcow2
```

This runs:

- `prepare` – clones/resizes the qcow2 disk, generates a cloud-init style ISO, and boots the VM once so it self-configures.
- `build` – packages the resulting disk as a `vagrant-libvirt` box plus metadata.

When it finishes, add the box to Vagrant (example name/IP only):

```bash
vagrant box add playbooks/checkpoint/checkpoint-r8120_10_194_58_200_metadata.json
```

You can now reference this box in the repo `Vagrantfile` or your own Vagrant environments.

---

## Run the Check Point playbooks

1. Ensure the VM you started from the box:
   - Uses the management IP you configured when building the box.
   - Is reachable over SSH.
   - Has API access enabled (auto-configured by the box builder script).
2. Edit `playbooks/checkpoint/vars_checkpoint.yml`:
   - Set `checkpoint_mgmt_ip`, API port/user/password, interface definitions, and objects/rules as needed.
3. From the repo root, run:

   ```bash
   ansible-playbook playbooks/checkpoint/checkpoint_configuration.yml --tags basic_config
   ansible-playbook playbooks/checkpoint/checkpoint_firewall_rules.yml --tags fw_rules
   ```

4. Validate on the gateway using the commands listed in `playbooks/checkpoint/checkpoint.md` (LLDP, OSPF, and policy checks).

This gives you a repeatable Check Point gateway instance and automation that fits into the wider NetSim lab.

