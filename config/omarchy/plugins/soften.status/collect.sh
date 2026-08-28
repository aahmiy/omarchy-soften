#!/usr/bin/env bash
#
# One JSON blob describing what is running on this machine, for the soften.status
# bar widget. Reads nothing privileged and starts nothing: two `systemctl`
# calls and one `ss`.
#
#   $1..  optional extra unit names to watch, on top of the built-in list.

set -uo pipefail
export LC_ALL=C

# Candidates, in the order they should appear. A unit that isn't installed is
# dropped, so the list below can stay generous without cluttering the panel.
UNITS=(
  postgresql "PostgreSQL"
  mariadb    "MariaDB"
  mysqld     "MySQL"
  mongodb    "MongoDB"
  redis      "Redis"
  valkey     "Valkey"
  memcached  "Memcached"
  clickhouse-server "ClickHouse"
  influxdb   "InfluxDB"
  rabbitmq   "RabbitMQ"
  elasticsearch "Elasticsearch"
  minio      "MinIO"
  docker     "Docker"
  containerd "containerd"
  podman     "Podman"
  libvirtd   "libvirt"
  nginx      "nginx"
  httpd      "Apache"
  caddy      "Caddy"
  ollama     "Ollama"
  sshd       "SSH"
  tailscaled "Tailscale"
)

for extra in "$@"; do
  UNITS+=("$extra" "$extra")
done

# One systemctl call for every candidate rather than one per unit.
names=()
for ((i = 0; i < ${#UNITS[@]}; i += 2)); do names+=("${UNITS[$i]}.service"); done
states="$(systemctl show --property=Id --property=LoadState --property=ActiveState \
            --property=SubState -- "${names[@]}" 2>/dev/null)"

ports="$(ss -H -tlnp 2>/dev/null)"

python3 - "$states" "$ports" "${UNITS[@]}" <<'PY'
import json, re, sys

raw_states, raw_ports = sys.argv[1], sys.argv[2]
pairs = sys.argv[3:]
labels = {pairs[i]: pairs[i + 1] for i in range(0, len(pairs) - 1, 2)}
order = [pairs[i] for i in range(0, len(pairs) - 1, 2)]

# `systemctl show` emits one blank-line-separated block per unit, in the order
# the units were asked for.
units = {}
for block in raw_states.split("\n\n"):
    fields = {}
    for line in block.splitlines():
        key, _, value = line.partition("=")
        fields[key] = value
    unit_id = fields.get("Id", "")
    if unit_id.endswith(".service"):
        units[unit_id[: -len(".service")]] = fields

services = []
for name in order:
    fields = units.get(name)
    if not fields or fields.get("LoadState") in (None, "", "not-found", "masked"):
        continue
    active = fields.get("ActiveState", "")
    sub = fields.get("SubState", "")
    if active == "active":
        state = "up"
    elif active == "failed" or sub == "failed":
        state = "failed"
    elif active == "activating":
        state = "starting"
    else:
        state = "down"
    services.append({"name": name, "label": labels.get(name, name), "state": state, "detail": sub})

# ss -H -tlnp columns: State Recv-Q Send-Q Local:Port Peer:Port [Process]
PROC = re.compile(r'\("([^"]+)",pid=(\d+)')
LOCAL_ONLY = ("127.", "[::1]", "::1")

seen, ports = set(), []
for line in raw_ports.splitlines():
    cols = line.split(None, 5)
    if len(cols) < 4:
        continue
    local = cols[3]
    addr, _, port = local.rpartition(":")
    if not port.isdigit():
        continue
    match = PROC.search(cols[5]) if len(cols) > 5 else None
    proc = match.group(1) if match else ""
    key = (port, proc)
    if key in seen:
        continue
    seen.add(key)
    ports.append({
        "port": int(port),
        "addr": addr,
        "proc": proc,
        # Anything not bound to loopback is reachable from the network.
        "exposed": not addr.startswith(LOCAL_ONLY),
    })

ports.sort(key=lambda entry: entry["port"])
json.dump({"services": services, "ports": ports}, sys.stdout)
PY
