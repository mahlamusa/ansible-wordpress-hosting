#!/usr/bin/env bash
# Tests the playbooks against fresh Ubuntu 24.04 and 26.04 containers.
#
# Uses rootless Podman so the containers can run systemd without root or
# privileged access on the host. Usage: tests/run.sh [--keep]
set -euo pipefail
cd "$(dirname "$0")/.."

ANSIBLE_BIN="${ANSIBLE_BIN:-tests/.venv/bin}"
PLAY="$ANSIBLE_BIN/ansible-playbook -i tests/inventory.ini -e @tests/test-vars.yml"
declare -A PORTS=([24.04]=2224 [26.04]=2226)

[[ -f tests/id_test ]] || ssh-keygen -q -t ed25519 -N '' -C awh-test -f tests/id_test

for v in "${!PORTS[@]}"; do
    name="awh-${v/./}"
    podman rm -f "$name" >/dev/null 2>&1 || true
    podman build -q --build-arg UBUNTU="$v" -t "awh-test:$v" tests >/dev/null
    # NET_ADMIN only covers the container's own network namespace; ufw needs it.
    podman run -d --name "$name" --cap-add NET_ADMIN,NET_RAW -p "127.0.0.1:${PORTS[$v]}:22" "awh-test:$v" >/dev/null
done
for v in "${!PORTS[@]}"; do
    timeout 60 bash -c "until podman exec awh-${v/./} systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded'; do sleep 1; done"
done

"$ANSIBLE_BIN/ansible-galaxy" collection install -r requirements.yml >/dev/null

echo "== Run 1: fresh provision as root"
$PLAY provision.yml

echo "== Run 2: provision again as sitemanager (must report no changes)"
$PLAY -e ansible_user=sitemanager provision.yml | tee tests/run2.log
grep -qE 'changed=[1-9]|failed=[1-9]' tests/run2.log && { echo "FAIL: second run not idempotent"; exit 1; }

echo "== Deploy the sample Node app"
$PLAY -e ansible_user=sitemanager deploy.yml

echo "== Deploy again (must report no changes)"
$PLAY -e ansible_user=sitemanager deploy.yml | tee tests/deploy2.log
grep -qE 'changed=[1-9]|failed=[1-9]' tests/deploy2.log && { echo "FAIL: second deploy not idempotent"; exit 1; }

echo "== Checks"
for v in "${!PORTS[@]}"; do
    c="awh-${v/./}"
    echo "-- $c"
    podman exec "$c" bash -ec '
        php_v=$(php -r "echo PHP_MAJOR_VERSION.\".\".PHP_MINOR_VERSION;")
        echo "PHP $php_v, opcache: $(php -m | grep -ci "zend opcache")"
        for s in nginx php$php_v-fpm mysql redis-server fail2ban ssh; do
            printf "%-14s %s\n" "$s" "$(systemctl is-active $s)"
        done
        nginx -t 2>&1 | tail -1
        wp --info --allow-root | grep -E "^(WP-CLI version|PHP version)"
        grep -h "" /etc/ssh/sshd_config.d/00-hardening.conf
        code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/ || true)
        echo "Unknown host -> HTTP ${code:-000} (000 = closed by 444 catch-all)"
        curl -sf -H "Host: localhost" http://127.0.0.1/
    '
    if ssh -i tests/id_test -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR \
        -p "${PORTS[${v}]}" root@127.0.0.1 true 2>/dev/null; then
        echo "FAIL: root SSH login still allowed"; exit 1
    fi
    echo "root SSH login refused"
done

[[ "${1:-}" == "--keep" ]] || podman rm -f awh-2404 awh-2604 >/dev/null
echo "All checks passed"
