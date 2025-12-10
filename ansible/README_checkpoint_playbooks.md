# CheckPoint Ansible Playbooks

Playbooks in this folder automate CheckPoint R81.20 lab devices in two passes:

- `checkpoint_config.yml` builds the base config over SSH/CLISH.
- `checkpoint_policy.yml` pushes objects and rules through the Management API.

## Playbooks

| File | What it does | How it connects |
|------|--------------|-----------------|
| `checkpoint_config.yml` | Locks the DB, sets hostname, configures interfaces/MTU, enables LLDP, enables OSPF per interface, saves config | SSH → CLISH |
| `checkpoint_policy.yml` | Clears session locks and existing rules/sections, optionally renames the gateway, creates network/host/group/multicast/service objects, publishes, adds new access rules, installs the policy, logs out | HTTPS API via `ansible.builtin.uri` |
| `vars_checkpoint.yml` | All inputs for both playbooks (interfaces, OSPF, LLDP, objects, rules, credentials) | n/a |

## Prerequisites

- Tested on CheckPoint R81.20 (should work on R80.x/R81.x with CLISH + API enabled).
- Ansible 2.9+ with built-in `ansible.builtin.uri`.
- SSH (22) to the gateway; HTTPS (443) to the management plane.
- API user with rights to publish/install (note: the bundled `vagrant` user lacks API access).
- Access to a Check Point firewall (this lab follows the appliance setup from this blog: xxxx).

## Configure your lab

Edit `vars_checkpoint.yml`:

- Management/API: `checkpoint_mgmt_ip`, `checkpoint_api_port`, `checkpoint_api_user/password`.
- Interfaces: names, `state`, descriptions, optional MTU and IPv4/mask.
- LLDP: `lldp_enabled`, TLVs, and `lldp_intf_disabled` list (keeps mgmt quiet).
- OSPF: `ospf_config` defaults, per-interface timers/cost/point-to-point/password.
- Objects and rules: `network_objects`, `network_groups`, `multicast_objects`, `service_objects`, `firewall_rules` (with rule `position` before the Cleanup rule).

## Running the playbooks

Run base config first, then the policy:

```bash
uv run ansible-playbook -i hosts.example.yml ansible/checkpoint_config.yml
uv run ansible-playbook -i hosts.example.yml ansible/checkpoint_policy.yml
```

The inventory host files `hosts.example.yml` supplies the necessary variables. If you are using netlab, use `hosts.yml` from the lab repository. This file is created automatically for you by `netlab create` which is part of `netlab up`.

## What the base config playbook does

- Locks the CheckPoint database to avoid concurrent edits.
- Sets hostname to the inventory host name.
- Configures each interface state/description/MTU/IPv4; enforces MTU again at the OS level to avoid dataplane drift.
- Enables LLDP globally, programs TLVs, and toggles transmit/receive per interface (skips ones listed in `lldp_intf_disabled`).
- Enables OSPF: router-id, area, and per-interface settings (cost/priority/hello/dead/passive/point-to-point/simple auth).
- Saves the configuration.

## What the firewall rules playbook does

- Logs in to the Management API and caches the session ID.
- Clears any uncommitted changes from other sessions and purges published sessions to prevent conflicts.
- Removes all existing access rules and sections from the policy layer (keeps one temporarily as placeholder).
- Optionally renames the gateway object to match `inventory_hostname` (publishes if changed).
- Creates network/host/group/multicast and TCP/UDP service objects, then publishes them.
- Creates new firewall sections and adds access rules at the given `position` values with comments/tracking.
- Removes the temporary placeholder rule and publishes the final configuration.
- Installs the specified package on the target gateway and polls the task to completion.
- Logs out and prints a short summary with object/rule counts and target.

## Handy checks on the gateway

```bash
clish -c "show ospf interface"
clish -c "show ospf neighbors"
clish -c "show lldp neighbors"
clish -c "show configuration ospf"
clish -c "show configuration lldp"
```
