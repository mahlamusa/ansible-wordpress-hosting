# WordPress Ansible

Playbooks for provisioning a WordPress hosting server on **Ubuntu 24.04 LTS or 26.04 LTS**. Originally based on [How to Install WordPress on Ubuntu](https://deliciousbrains.com/hosting-wordpress-setup-secure-virtual-server/).

Out of the box it handles:

* Admin users with key-only SSH login and passwordless sudo
* SSH hardening (no root login, no password login)
* Firewall (ufw: only SSH, HTTP and HTTPS open)

And installs, from Ubuntu's own repositories:

| Software | Ubuntu 24.04 | Ubuntu 26.04 |
| --- | --- | --- |
| Nginx | 1.24 | 1.28 |
| PHP-FPM + WordPress extensions | 8.3 | 8.5 |
| MySQL | 8.0 | 8.4 |
| Redis | 7.0 | 8.0 |
| Node.js + PM2 | 18 | 22 |
| WP-CLI, Certbot, Fail2Ban, Git | ✓ | ✓ |

## Requirements

* ansible-core 2.18 or newer (tested with 2.21). Upgrade an older pipx install with `pipx upgrade ansible`.
* The collections in `requirements.yml`:

```
ansible-galaxy collection install -r requirements.yml
```

## Usage

1. Add your server(s) to `hosts` under `[dev]`.
2. Review `group_vars/all.yml`. At minimum, check `admin_users`. By default it creates `sitemanager` with your `~/.ssh/id_ed25519.pub` as its login key.
3. Provision (the first run connects as root):

```
ansible-playbook provision.yml
```

4. Root SSH login is now disabled. Change `ansible_user` in `hosts` to one of your admin users for later runs.

### Other playbooks

| Playbook | What it does |
| --- | --- |
| `deploy.yml` | Copies a Node app from `node_app_src`, installs its dependencies, runs it with PM2 and proxies `node_app_server_name` to it through nginx. Example: `ansible-playbook deploy.yml -e node_app_src=~/path/to/app` |
| `certbot.yml` | Gets Let's Encrypt certificates. Example: `ansible-playbook certbot.yml -e '{"certbot_domains":["example.com"]}'` |
| `nginx.yml` | Re-applies the nginx and PHP configuration only. |
| `users.yml` | Re-applies the admin users only. |

## Testing

`tests/run.sh` provisions fresh Ubuntu 24.04 and 26.04 containers, runs everything twice to check nothing changes on the second run, deploys a sample app, and checks the services. It uses rootless [Podman](https://podman.io/) so the containers can run systemd without root on your machine. Install it with `sudo apt install podman`.

```
python3 -m venv tests/.venv && tests/.venv/bin/pip install ansible-core ansible-lint
tests/run.sh          # add --keep to leave the containers running
```
