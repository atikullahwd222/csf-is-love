#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root."
    exit 1
fi

if ! command -v imunify360-agent >/dev/null 2>&1; then
    echo "imunify360-agent not found. Install Imunify360 first, then run this script."
    exit 1
fi

echo "Applying Imunify360 recommended baseline..."
imunify360-agent config update '{"DOS":{"enabled":true,"default_limit":100}}' || true
imunify360-agent config update '{"ENHANCED_DOS":{"enabled":true,"default_limit":100}}' || true
imunify360-agent config update '{"CSF_INTEGRATION":{"catch_lfd_events":true}}' || true
imunify360-agent config update '{"CPANEL_ACCOUNT_PROTECTION":{"enable":true}}' || true
imunify360-agent config update '{"OSSEC":{"active_response":true}}' || true
imunify360-agent config update '{"WEBSHIELD":{"enable":true,"known_proxies_support":true}}' || true
imunify360-agent config update '{"PAM":{"enable":true,"exim_dovecot_protection":true,"ftp_protection":true}}' || true
imunify360-agent config update '{"MOD_SEC":{"ruleset":"FULL"}}' || true

if command -v systemctl >/dev/null 2>&1; then
    systemctl restart imunify360 || true
fi

echo "Imunify360 baseline applied. Some options depend on the installed Imunify360 version/license."
