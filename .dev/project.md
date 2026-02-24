# Project Context

## Overview

**ndknitor-playbooks** — Ansible playbooks for deploying a highly-available 3-node cluster with etcd, Docker, Keepalived, UFW firewall, Nginx TCP proxy, and DNS mesh.

Target environment: 3 Debian Bookworm VMs (kn1-3.ndkn.local) at 192.168.56.101-103, provisioned via Vagrant/VirtualBox.

## Tech Stack

### Languages
- YAML (Ansible playbooks and roles)
- Jinja2 (configuration templates)
- Python 3 (preseed.py — Debian preseed HTTP server)
- Bash (cert/cert.sh — TLS certificate generation with cfssl)

### Frameworks
- Ansible 2.1+
- Vagrant (VirtualBox provider)

### Testing
- No automated testing framework (Molecule not configured)
- Manual testing via Vagrant VMs

### Build Tools
- ansible-playbook (deployment)
- ansible-galaxy (role scaffolding)

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `playbooks/` | Orchestration playbooks — one per service/concern |
| `roles/` | Reusable Ansible roles (8 roles) |
| `inventories/production/` | Production inventory with host groups |
| `cert/` | TLS certificate generation scripts (cfssl) |
| `assets/` | Static files referenced by roles (e.g., CA cert) |

## Architecture

### Style
Infrastructure as Code (IaC) — Role-based Ansible architecture with modular, independent roles.

### Layers
| Layer | Directory | Purpose |
|-------|-----------|---------|
| Orchestration | `playbooks/` | Define vars, target host groups, include roles |
| Role Logic | `roles/*/tasks/` | Sequential task execution, can include subtasks |
| Templates | `roles/*/templates/` | Jinja2 config file templates (.j2) |
| Default Vars | `roles/*/defaults/` | Lowest precedence variables (mostly empty) |
| Role Vars | `roles/*/vars/` | Higher precedence variables (mostly empty) |
| Handlers | `roles/*/handlers/` | Service restart/reload on config changes |
| Metadata | `roles/*/meta/` | Role dependencies and galaxy info |
| Inventory | `inventories/production/` | Host definitions and group assignments |

### Roles

| Role | Purpose |
|------|---------|
| `initialize` | Base system setup (sudo, SSH hardening, static IP, DNS) |
| `dns_host_mesh` | Populate /etc/hosts with all cluster nodes |
| `firewall` | UFW firewall with CIDR-based inbound/outbound rules |
| `docker` | Install Docker CE from official repository |
| `root_ca` | Install custom root CA certificate |
| `etcd` | Deploy etcd cluster with mutual TLS |
| `keepalived` | HA via VRRP with VIP 192.168.56.100 |
| `publish_tcp` | Nginx TCP stream proxy with ACLs |

### Playbooks

| Playbook | Targets | Role |
|----------|---------|------|
| `initialize.yml` | all | initialize |
| `dns_host_mesh.yml` | all | dns_host_mesh |
| `firewall.yml` | all | firewall |
| `docker.yml` | docker | docker |
| `root_ca.yml` | all | root_ca |
| `etcd.yml` | etcd | etcd |
| `keepalived.yml` | keepalived | keepalived |
| `publish_tcp.yml` | all | publish_tcp |
| `upgrade.yml` | all | (inline apt upgrade) |

### Key Patterns

- **Variable passing**: Playbook-level `vars:` rather than role defaults — centralizes configuration
- **Per-host rule selection**: `set_fact` with `rules[inventory_hostname] | default(rules['all'])` for host-specific overrides
- **TLS cert distribution**: Generate on first node (delegate_to), fetch to controller, distribute to all
- **Dynamic cluster membership**: Build cluster strings from inventory groups with Jinja2 filters
- **Service installation**: apt prerequisites → GPG key → repository → install → systemd enable
- **Config deployment**: Template .j2 → deploy → notify handler for restart/reload
- **Idempotency**: `creates:` argument on command tasks, `state: present` for packages
- **Dynamic priority**: `play_hosts.index()` for automatic master/backup assignment (keepalived)

## Conventions

### Naming
- Roles: `snake_case` (e.g., `dns_host_mesh`, `publish_tcp`, `root_ca`)
- Playbooks: Match role name (e.g., `playbooks/docker.yml` → `roles/docker`)
- Tasks: Descriptive present tense, starts with verb (e.g., `Install Docker`, `Ensure UFW is installed`)
- Variables: `snake_case` (e.g., `etcd_version`, `keepalived_vip`, `dns_servers`)
- Handlers: "Action service" format (e.g., `Restart etcd`, `Reload nginx`)
- Templates: `.j2` extension (e.g., `etcd.service.j2`, `nginx.conf.j2`)

### Code Style
- SPDX license header: `#SPDX-License-Identifier: MIT-0`
- Mix of FQCN and short module names (not yet standardized)
- `become: true` set at playbook level
- Handlers for service restarts after config changes

### Testing
- No automated tests currently
- Local testing via Vagrant VMs
- Check mode: `ansible-playbook -C` for dry runs

### Git
- Descriptive commit messages (e.g., "preseed completion", "DNS servers", "Root CA playbook")
- Single main branch

## Build Commands

| Command | Purpose |
|---------|---------|
| `ansible-playbook -i inventories/production/hosts.yml -u vagrant --private-key ./key playbooks/<name>.yml --ask-become-pass` | Run a playbook |
| `ansible-galaxy init roles/<role_name>` | Scaffold a new role |
| `vagrant up` | Provision test VMs |
| `vagrant destroy -f` | Tear down test VMs |

## Inventory

3-node cluster with shared group membership:

```yaml
all:
  hosts:
    kn1.ndkn.local: { ansible_host: 192.168.56.101 }
    kn2.ndkn.local: { ansible_host: 192.168.56.102 }
    kn3.ndkn.local: { ansible_host: 192.168.56.103 }
  children:
    etcd: [kn1, kn2, kn3]
    keepalived: [kn1, kn2, kn3]
    docker: [kn1, kn2, kn3]
```

## Notes

- Passwords exist in plaintext in playbooks (keepalived auth_pass) — consider Ansible Vault
- Certificate validity: 365 days for server certs — plan for renewal
- Firewall role resets all rules on every run (temporarily drops connections)
- No role-to-role dependencies defined in meta — roles are fully independent
- `community.general` collection required for UFW module
