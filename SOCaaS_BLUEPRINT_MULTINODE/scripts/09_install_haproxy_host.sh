#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Installing HAProxy on Parrot host"
sudo apt update
sudo apt install -y haproxy

if [[ -f /etc/haproxy/haproxy.cfg ]]; then
  backup_dir="${SOCAAS_BACKUPS_DIR}/haproxy"
  mkdir -p "${backup_dir}"
  sudo cp /etc/haproxy/haproxy.cfg "${backup_dir}/haproxy.cfg.bak.$(date +%Y%m%d-%H%M%S)"
fi

log "Writing /etc/haproxy/haproxy.cfg"
sudo tee /etc/haproxy/haproxy.cfg >/dev/null <<EOF_CFG
global
    log /dev/log local0
    log /dev/log local1 notice
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    retries 3
    option redispatch
    timeout connect 5s
    timeout client 1m
    timeout server 1m

frontend k8s-api
    bind *:6443
    mode tcp
    default_backend k8s-masters

backend k8s-masters
    mode tcp
    balance roundrobin
    option tcp-check
    server master1 ${SOCAAS_MASTER_IP}:6443 check fall 3 rise 2

frontend wazuh-agent-events
    bind *:${SOCAAS_WAZUH_AGENT_TCP_PORT}
    mode tcp
    default_backend wazuh-agent-events-backend

backend wazuh-agent-events-backend
    mode tcp
    balance leastconn
    server worker1 ${SOCAAS_WORKER1_IP}:31514 check fall 3 rise 2

frontend wazuh-enrollment
    bind *:${SOCAAS_WAZUH_ENROLL_PORT}
    mode tcp
    default_backend wazuh-enrollment-backend

backend wazuh-enrollment-backend
    mode tcp
    balance leastconn
    server worker1 ${SOCAAS_WORKER1_IP}:31515 check fall 3 rise 2

frontend wazuh-api
    bind *:${SOCAAS_WAZUH_API_PORT}
    mode tcp
    default_backend wazuh-api-backend

backend wazuh-api-backend
    mode tcp
    balance roundrobin
    server worker1 ${SOCAAS_WORKER1_IP}:31550 check fall 3 rise 2

frontend wazuh-manager-compat
    bind *:${SOCAAS_WAZUH_MANAGER_COMPAT_PORT}
    mode tcp
    default_backend wazuh-agent-events-backend

frontend wazuh-dashboard
    bind *:${SOCAAS_WAZUH_DASHBOARD_PORT}
    mode tcp
    default_backend wazuh-dashboard-backend

backend wazuh-dashboard-backend
    mode tcp
    balance roundrobin
    server worker1 ${SOCAAS_WORKER1_IP}:30002 check fall 3 rise 2

frontend shuffle-ui
    bind *:${SOCAAS_SHUFFLE_UI_PORT}
    mode tcp
    default_backend shuffle-ui-backend

backend shuffle-ui-backend
    mode tcp
    balance roundrobin
    server worker2 ${SOCAAS_WORKER2_IP}:30080 check fall 3 rise 2

frontend thehive-ui
    bind *:${SOCAAS_THEHIVE_UI_PORT}
    mode tcp
    default_backend thehive-ui-backend

backend thehive-ui-backend
    mode tcp
    balance roundrobin
    server worker2 ${SOCAAS_WORKER2_IP}:30900 check fall 3 rise 2

listen stats
    bind *:${SOCAAS_HAPROXY_STATS_PORT}
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats auth admin:admin
EOF_CFG

sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl enable --now haproxy
sudo systemctl reload haproxy
sudo ss -tlnp | grep haproxy || true
log "HAProxy is configured. Stats: http://${SOCAAS_HOST_BRIDGE_IP}:${SOCAAS_HAPROXY_STATS_PORT}/stats"
