#!/usr/bin/env bash
set -euo pipefail

CSF_URL="${CSF_URL:-https://download.configserver.com/csf.tgz}"
TMP_DIR=""
timestamp="$(date +%Y%m%d%H%M%S)"

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: setup-linux.sh must be run as root"
    exit 1
fi

if [ -d /usr/local/cpanel ]; then
    echo "ERROR: cPanel/WHM detected. Use setup.sh for WHM servers instead."
    exit 1
fi

install_packages() {
    echo "Installing required packages..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            curl wget tar gzip perl libwww-perl liblwp-protocol-https-perl \
            iptables ipset iproute2 net-tools dnsutils unzip
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y \
            curl wget tar gzip perl perl-libwww-perl perl-LWP-Protocol-https \
            iptables ipset iproute net-tools bind-utils unzip
    elif command -v yum >/dev/null 2>&1; then
        yum install -y \
            curl wget tar gzip perl perl-libwww-perl perl-LWP-Protocol-https \
            iptables ipset iproute net-tools bind-utils unzip
    else
        echo "ERROR: apt-get, dnf, or yum is required"
        exit 1
    fi
}

download_file() {
    local url="$1"
    local dest="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        echo "ERROR: curl or wget is required"
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

install_csf() {
    if command -v csf >/dev/null 2>&1 && [ -f /etc/csf/csf.conf ]; then
        echo "CSF already installed. Keeping current install and applying hardening."
        return
    fi

    echo "Installing CSF for plain Linux..."
    TMP_DIR="$(mktemp -d)"
    download_file "$CSF_URL" "$TMP_DIR/csf.tgz"
    tar -xzf "$TMP_DIR/csf.tgz" -C "$TMP_DIR"
    cd "$TMP_DIR/csf"
    sh install.sh
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

apply_hardening() {
    echo "Applying BIT Linux CSF hardening..."
    backup_file /etc/csf/csf.conf

    set_csf_option TESTING "0"
    set_csf_option RESTRICT_SYSLOG "3"
    set_csf_option DROP_ONLYRES "1"
    set_csf_option DROP_NOLOG "23,67,68,111,113,135:139,445,500,513,520,5678,17500"
    set_csf_option PORTFLOOD "22;tcp;5;300,80;tcp;250;5,443;tcp;250;5"
    set_csf_option LF_DAEMON "1"
    set_csf_option LF_SSHD "5"
    set_csf_option LF_FTPD "10"
    set_csf_option LF_SMTPAUTH "5"
    set_csf_option LF_POP3D "10"
    set_csf_option LF_IMAPD "10"
    set_csf_option LF_PERMBLOCK "1"
    set_csf_option LF_PERMBLOCK_COUNT "4"
    set_csf_option LF_PERMBLOCK_ALERT "1"
    set_csf_option DENY_IP_LIMIT "300"
    set_csf_option DENY_TEMP_IP_LIMIT "200"

    echo "kernel.printk = 3 4 1 3" > /etc/sysctl.d/99-quiet-console.conf
    sysctl --system >/dev/null || true

    mkdir -p /usr/local/csf
    echo "BIT Linux CSF hardening $timestamp" > /usr/local/csf/bit-linux-hardening.txt
}

restart_services() {
    echo "Restarting CSF and lfd..."
    csf -r || true
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable csf lfd >/dev/null 2>&1 || true
        systemctl restart lfd || true
    elif command -v service >/dev/null 2>&1; then
        service lfd restart || true
    fi
}

install_packages
install_csf
apply_hardening
restart_services

echo "Done. Plain Linux CSF hardening applied."
