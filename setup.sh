#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: setup.sh must be run as root"
    exit 1
fi

if [ ! -d /usr/local/cpanel ] || [ ! -x /usr/local/cpanel/cpanel ]; then
    echo "ERROR: cPanel/WHM was not detected on this server"
    exit 1
fi

cd "$(dirname "$0")"

timestamp="$(date +%Y%m%d%H%M%S)"

install_csf() {
    if command -v csf >/dev/null 2>&1 && [ -d /etc/csf ]; then
        return
    fi

    echo "Installing cpanel-csf..."
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y cpanel-csf
    elif command -v yum >/dev/null 2>&1; then
        yum install -y cpanel-csf
    elif command -v apt >/dev/null 2>&1; then
        apt update
        apt install -y cpanel-csf
    else
        echo "ERROR: No supported package manager found"
        exit 1
    fi
}

backup_file() {
    local file="$1"
    if [ -e "$file" ]; then
        cp -a "$file" "$file.bak.$timestamp"
        echo "Backup: $file.bak.$timestamp"
    fi
}

set_csf_option() {
    local key="$1"
    local value="$2"

    if grep -qE "^${key}[[:space:]]*=" /etc/csf/csf.conf; then
        sed -i "s|^${key}[[:space:]]*=.*|${key} = \"${value}\"|" /etc/csf/csf.conf
    else
        printf '%s = "%s"\n' "$key" "$value" >> /etc/csf/csf.conf
    fi
}

install_csf

echo "Backing up current files..."
backup_file /etc/csf/csf.conf
backup_file /usr/local/csf/lib/ConfigServer/DisplayUI.pm
backup_file /usr/local/cpanel/whostmgr/docroot/cgi/configserver/csf.cgi
backup_file /usr/local/cpanel/whostmgr/docroot/templates/csf.tmpl

echo "Installing modified WHM UI files..."
install -m 0644 lib/ConfigServer/DisplayUI.pm /usr/local/csf/lib/ConfigServer/DisplayUI.pm
install -m 0700 cpanel/csf.cgi /usr/local/cpanel/whostmgr/docroot/cgi/configserver/csf.cgi
install -m 0644 cpanel/csf.tmpl /usr/local/cpanel/whostmgr/docroot/templates/csf.tmpl

echo "Applying CSF settings..."
set_csf_option DROP_ONLYRES "1"
set_csf_option DROP_NOLOG "23,67,68,111,113,135:139,445,500,513,520,5678,17500"
set_csf_option PORTFLOOD "22;tcp;5;300,80;tcp;250;5,443;tcp;250;5"
set_csf_option RESTRICT_SYSLOG "3"

echo "Applying quiet kernel console logging..."
echo "kernel.printk = 3 4 1 3" > /etc/sysctl.d/99-quiet-console.conf
sysctl --system >/dev/null || true

echo "Registering WHM plugin..."
touch /usr/local/cpanel/Cpanel/Config/ConfigObj/Driver || true
/usr/local/cpanel/bin/register_appconfig /usr/local/cpanel/bin/csf.conf.appconfig || true

echo "Restarting services..."
csf -r || true
systemctl restart lfd || true

if [ -x /scripts/restartsrv_cpsrvd ]; then
    /scripts/restartsrv_cpsrvd || true
elif [ -x /usr/local/cpanel/scripts/restartsrv_cpsrvd ]; then
    /usr/local/cpanel/scripts/restartsrv_cpsrvd || true
fi

echo "Done. Open WHM > Plugins > ConfigServer Security & Firewall."
