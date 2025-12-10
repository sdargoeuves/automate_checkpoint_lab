# Check Point R81.20 Lab Automation

This directory contains everything needed to spin up and automate a Check Point R81.20 gateway for the lab: a Vagrant box builder and Ansible playbooks.

---

## Prerequisites

This project uses [uv](https://docs.astral.sh/uv/) for dependency management, making it easy for anyone to run the Ansible playbooks without manually setting up Python environments.

Install uv:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

All Ansible dependencies are managed via `pyproject.toml` and will be automatically installed when you run commands through uv. **No need to run `uv sync` or manually install dependencies** - `uv run` handles everything for you!

---

## Project Structure

```bash
├── bash/
│   ├── checkpoint_box_builder.sh
│   └── README_checkpoint_box_builder.md
├── ansible/
│   ├── checkpoint_config.yml
│   ├── checkpoint_policy.yml
│   ├── vars_checkpoint.yml
│   ├── hosts.example.yml
│   └── README_checkpoint_playbooks.md
├── pyproject.toml
└── README.md
```

## Components

- `bash/checkpoint_box_builder.sh` – converts an official R81.20 qcow2 image into a reusable `vagrant-libvirt` box with:
  - Fixed management IP/hostname.
  - First Time Wizard preconfigured (standalone gateway + management).
  - Local admin + expert passwords for lab use.
  - A `vagrant` user (SSH key + sudo) for automation.
- `ansible/checkpoint_config.yml` – base configuration playbook:
  - Locks the DB, sets hostname, configures interfaces/MTU, enables LLDP and OSPF, then saves the configuration.
- `ansible/checkpoint_policy.yml` – policy playbook:
  - Talks to the Management API, (optionally) renames the gateway object, creates network/host/group/multicast/service objects, adds rules, installs policy, and logs out.
- `ansible/vars_checkpoint.yml` – all variables for both playbooks:
  - Interfaces, LLDP/OSPF parameters, objects, firewall rules, and credentials.

For detailed explanations:

- Box builder: `bash/README_checkpoint_box_builder.md`
- Playbooks: `ansible/README_checkpoint_playbooks.md`

---

## Build the Check Point Vagrant box

From the repo root, with an R81.20 qcow2 image available (for example `cp_r81_20_disk.qcow2`):

```bash
bash/checkpoint_box_builder.sh auto --disk ../cp_r81_20_disk.qcow2
```

This runs:

- `prepare` – clones/resizes the qcow2 disk, generates a cloud-init style ISO, and boots the VM once so it self-configures.
- `build` – packages the resulting disk as a `vagrant-libvirt` box plus metadata.

When it finishes, add the box to Vagrant (example name/IP only):

```bash
vagrant box add checkpoint-r8120_10_194_58_200_metadata.json
```

You can now reference this box in the repo `Vagrantfile` or your own Vagrant environments.

---

## Run the Check Point playbooks

1. Ensure the VM you started from the box:
   - Uses the management IP you configured when building the box.
   - Is reachable over SSH.
   - Has API access enabled (auto-configured by the box builder script).
2. Edit `ansible/vars_checkpoint.yml`, unless you are using netlab, in which case the variables are already in the `hosts.yml` file:
   - Set `checkpoint_mgmt_ip`, API port/user/password, interface definitions, and objects/rules as needed.
3. From the repo root, run the playbooks using uv:

   ```bash
   uv run ansible-playbook -i hosts.example.yml ansible/checkpoint_config.yml
   uv run ansible-playbook -i hosts.example.yml ansible/checkpoint_policy.yml
   ```

   The `uv run` command automatically installs the required Ansible dependencies and runs the playbooks in an isolated environment.

4. Validate on the gateway using the commands listed in `ansible/README_checkpoint_playbooks.md` (LLDP, OSPF, and policy checks).

This gives you a repeatable Check Point gateway instance and automation that fits into the wider lab.
