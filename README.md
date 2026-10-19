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

Node.js 18 (Ubuntu 24.04) is past its upstream end of life; Ubuntu still ships security fixes for it.

## Requirements

* ansible-core 2.18 or newer (tested with 2.21). Upgrade an older pipx install with `pipx upgrade ansible`.
* The collections in `requirements.yml` (installed into `./collections`, which is gitignored):

```
ansible-galaxy collection install -r requirements.yml
```

* A server running Ubuntu 24.04 or 26.04 that you can reach over SSH as root with a key.

## Quick start

1. Add your server(s) to `hosts` under `[dev]`.
2. Review the [options](#options) in `group_vars/all.yml`. At minimum, check `admin_users`. By default it creates `sitemanager` with your `~/.ssh/id_ed25519.pub` as its login key.
3. Provision (the first run connects as root):

   ```
   ansible-playbook provision.yml
   ```

4. Root SSH login is now disabled. In `hosts`, change `ansible_user=root` to one of your admin users for all later runs.
5. Optionally deploy a Node app and get certificates (see below).

## Playbooks

All playbooks target the `dev` inventory group and run with `become: true`. Use `--limit <host>` to run against a single server.

### `provision.yml`: full server setup

Runs these roles in order:

| Role | What it does |
| --- | --- |
| `common` | Safe-upgrades all packages; installs `acl`, `at`, `ca-certificates`, `curl`, `fail2ban`, `git`, `jq`, `redis-server`, `rsync`, `unzip`; enables Fail2Ban and Redis. |
| `users` | Creates each user in `admin_users` (groups `sudo` and `www-data`), adds their SSH key, and gives them passwordless sudo via `/etc/sudoers.d/<name>-user`. |
| `ufw` | Installs ufw, allows TCP 22, 80 and 443, then enables the firewall with a default deny. Skipped if `ufw_enabled` is false. |
| `php` | Installs PHP-FPM with the bcmath, cli, curl, gd, igbinary, imagick, intl, mbstring, mysql, redis, soap, xml, xmlrpc and zip extensions. Detects the installed version, runs the FPM pool as `web_user` and sets the upload limits. |
| `nginx` | Installs nginx, backs up the original `/etc/nginx` once to `/etc/nginx.orig`, copies the config kit from `roles/nginx/nginx/`, renders `nginx.conf` (workers run as `web_user`) and the PHP upstream, enables a catch-all default site, and validates with `nginx -t`. |
| `mysql` | Installs and enables MySQL server. |
| `wp_cli` | Installs WP-CLI to `/usr/bin/wp` with bash tab completion. |
| `nodejs` | Installs Node.js and npm from Ubuntu, and PM2 globally. |
| `letsencrypt` | Installs certbot and its nginx plugin. The package's systemd timer handles renewals. |
| `ssh` | Writes `/etc/ssh/sshd_config.d/00-hardening.conf` (no password or keyboard-interactive login; root login per `ssh_disable_root_login`), validated with `sshd -t`. Refuses to disable root login if `admin_users` is empty. |

```
ansible-playbook provision.yml
```

### `deploy.yml`: deploy a Node app

Run after `provision.yml`. Runs the `node_app` role, which:

1. Copies `node_app_src` from your machine to `node_app_dest` with rsync, owned by `web_user:www-data`. `node_modules` and `.git` are excluded.
2. Runs `npm install` as `web_user`.
3. Starts `index.js` with PM2 as `node_app_name`, or reloads it if the code or dependencies changed.
4. Registers PM2 to start on boot (`pm2-<web_user>` systemd service) and saves the process list.
5. Creates an nginx site that proxies `node_app_server_name` to `127.0.0.1:node_app_port`, enables it, and validates the config.

The app's entry point must be `index.js`, and it must listen on `node_app_port`.

```
ansible-playbook deploy.yml -e node_app_src=~/path/to/app
```

### `certbot.yml`: Let's Encrypt certificates

Requests a certificate for each domain in `certbot_domains`, using the nginx plugin to answer the challenge. Domains that already have a certificate in `/etc/letsencrypt/live/` are skipped. Each domain's DNS must already point at the server.

This uses `certbot certonly`, so your nginx site files are not changed. Add the HTTPS server block yourself and include `global/server/ssl.conf` (see [Nginx config kit](#nginx-config-kit)).

```
ansible-playbook certbot.yml -e '{"certbot_domains":["example.com","www.example.com"]}'
```

### `nginx.yml`: re-apply nginx and PHP config

Runs the `php` and `nginx` roles only. PHP is included because the nginx upstream needs the detected PHP version. Use it after editing files under `roles/nginx/`.

```
ansible-playbook nginx.yml
```

### `users.yml`: re-apply admin users

Runs the `users` role only. Use it after adding a user or key to `admin_users`. It never removes users.

```
ansible-playbook users.yml
```

## Options

Defaults live in `group_vars/all.yml`. Override them there, in `host_vars/<host>.yml`, or with `-e` on the command line.

### Server

| Variable | Default | Description |
| --- | --- | --- |
| `web_user` | `sitemanager` | Account that nginx workers, PHP-FPM and the Node app run as. It must also be listed in `admin_users`, which is what creates the account. |
| `admin_users` | `sitemanager` with `~/.ssh/id_ed25519.pub` | List of admin accounts. Each item needs `name` and `public_key` (the key text, not a path; use `lookup('ansible.builtin.file', '<path>')` to read a file). See the example below. |
| `ssh_disable_root_login` | `true` | `true` sets `PermitRootLogin no`. `false` sets `prohibit-password`, so root can still log in with a key. |
| `ufw_enabled` | `true` | Set to `false` where the firewall can't be managed (some containers or VPS types). ufw is still installed. |

Adding a second admin:

```yaml
admin_users:
  - name: "{{ web_user }}"
    public_key: "{{ lookup('ansible.builtin.file', '~/.ssh/id_ed25519.pub') }}"
  - name: alice
    public_key: "ssh-ed25519 AAAA... alice@laptop"
```

### PHP

| Variable | Default | Description |
| --- | --- | --- |
| `php_upload_max_filesize` | `128M` | `upload_max_filesize` in the FPM `php.ini`. |
| `php_post_max_size` | `128M` | `post_max_size` in the FPM `php.ini`. Keep it at least as large as the upload limit. |
| `php_version` | detected | Not an option: the `php` role sets it from the installed PHP (`8.3` or `8.5`). |

nginx's own body size limit (`client_max_body_size 64m`) is in `roles/nginx/nginx/global/limits.conf`. Raise it too if you raise the PHP limits above 64M.

### Let's Encrypt

| Variable | Default | Description |
| --- | --- | --- |
| `certbot_email` | `webmaster@conflated.co.za` | Email for the Let's Encrypt account and expiry notices. |
| `certbot_domains` | `[]` | Domains to request certificates for. `certbot.yml` fails if this is empty. |

### Node app

| Variable | Default | Description |
| --- | --- | --- |
| `node_app_src` | `""` | Local path of the app to deploy. Required by `deploy.yml`. |
| `node_app_dest` | `/usr/share/nginx/html` | Path on the server where the app is copied. |
| `node_app_name` | `site-manager-api` | PM2 process name, also used as the nginx site file name. |
| `node_app_port` | `3000` | Port nginx proxies to. Your app must listen on it. |
| `node_app_server_name` | the inventory hostname | nginx `server_name` for the app. Set it to your domain(s), space separated. |

### Inventory

| Variable | Where | Description |
| --- | --- | --- |
| `ansible_user` | `hosts` | SSH user. `root` for the first provision, then one of `admin_users`. |
| `ansible_ssh_private_key_file` | `hosts` (optional) | Private key to connect with, if not your default. |

## Nginx config kit

`roles/nginx/nginx/` is copied to `/etc/nginx/`. Besides the http-level config (gzip, limits, MIME types, PHP upstream), it provides snippets to `include` in your site's `server` block:

| File | Use |
| --- | --- |
| `global/server/defaults.conf` | Includes `exclusions.conf`, `security.conf` and `static-files.conf`. Recommended for every site. |
| `global/server/exclusions.conf` | Denies hidden files, `.ini`/`.log`/`.conf` files, and PHP files in uploads. |
| `global/server/security.conf` | Hides the nginx version and sets security headers. |
| `global/server/static-files.conf` | Cache headers for static assets. |
| `global/server/ssl.conf` | TLS 1.2/1.3 settings, the bundled DH params, and HSTS. |
| `global/server/fastcgi-cache.conf` | WordPress-aware FastCGI page caching rules. |
| `global/server/multisite-subdirectory.conf` | Rewrites for subdirectory multisite. |
| `global/fastcgi-params.conf` | FastCGI parameters for PHP locations. |

Use `fastcgi_pass $upstream;` in PHP locations to reach the detected PHP-FPM version. The default site (`sites-available/default`) closes connections for unknown hostnames (HTTP 444).

## Testing

`tests/run.sh` provisions fresh Ubuntu 24.04 and 26.04 containers and checks:

* a first provision as root, then a second run as `sitemanager` that must report no changes
* deploying a sample app (`tests/app`) twice, the second with no changes
* nginx, PHP-FPM, MySQL, Redis, Fail2Ban and ssh are running, `nginx -t` passes, WP-CLI works, the app is served through nginx, and root SSH login is refused

It uses rootless [Podman](https://podman.io/), so the containers run systemd without root on your machine. Install it with `sudo apt install podman`.

```
python3 -m venv tests/.venv && tests/.venv/bin/pip install ansible-core ansible-lint
tests/run.sh          # add --keep to leave the containers running
```

| Setting | Description |
| --- | --- |
| `--keep` | Leave the containers (`awh-2404` on port 2224, `awh-2604` on port 2226) running afterwards. |
| `ANSIBLE_BIN` | Directory with the Ansible binaries to use. Defaults to `tests/.venv/bin`. |

Test overrides (test SSH key, sample app, `localhost` server name) are in `tests/test-vars.yml`.

Lint with:

```
PATH=$PWD/tests/.venv/bin:$PATH ansible-lint
```

## Notes

* `vault.yml` is an encrypted Ansible Vault file that no playbook currently uses.
