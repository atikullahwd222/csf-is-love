#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root."
    exit 1
fi

if ! command -v whmapi1 >/dev/null 2>&1; then
    echo "whmapi1 not found. This script must run on a cPanel/WHM server."
    exit 1
fi

echo "Applying cPHulk recommended baseline..."
whmapi1 enable_cphulk
whmapi1 set_cphulk_config_key key=brute_force_period_mins value=10 || true
whmapi1 set_cphulk_config_key key=max_failures value=10 || true
whmapi1 set_cphulk_config_key key=ip_brute_force_period_mins value=15 || true
whmapi1 set_cphulk_config_key key=max_failures_byip value=15 || true
whmapi1 set_cphulk_config_key key=mark_as_brute value=50 || true
whmapi1 set_cphulk_config_key key=country_whitelist value=BD || true

if [[ -x /usr/local/cpanel/scripts/restartsrv_cphulkd ]]; then
    /usr/local/cpanel/scripts/restartsrv_cphulkd
elif [[ -x /scripts/restartsrv_cphulkd ]]; then
    /scripts/restartsrv_cphulkd
else
    systemctl restart cphulkd || true
fi

echo "cPHulk baseline applied."
