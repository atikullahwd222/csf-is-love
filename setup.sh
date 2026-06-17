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

REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/atikullahwd222/csf-is-love/refs/heads/main}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
TMP_DIR=""

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

fetch_file() {
    local path="$1"
    local dest="$2"
    local url="$REPO_RAW_URL/$path"

    mkdir -p "$(dirname "$dest")"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        echo "ERROR: curl or wget is required to fetch $path"
        exit 1
    fi
}

prepare_sources() {
    if [ -f "$SOURCE_DIR/lib/ConfigServer/DisplayUI.pm" ] \
        && [ -f "$SOURCE_DIR/cpanel/csf.cgi" ] \
        && [ -f "$SOURCE_DIR/cpanel/csf.tmpl" ] \
        && [ -f "$SOURCE_DIR/csf/configserver.css" ] \
        && [ -f "$SOURCE_DIR/BAHARI_VERSION" ] \
        && [ -f "$SOURCE_DIR/BAHARI_CHANGELOG.md" ]; then
        return
    fi

    echo "Local repo files not found; fetching required files from BahariHost's Server..."
    TMP_DIR="$(mktemp -d)"
    fetch_file "lib/ConfigServer/DisplayUI.pm" "$TMP_DIR/lib/ConfigServer/DisplayUI.pm"
    fetch_file "cpanel/csf.cgi" "$TMP_DIR/cpanel/csf.cgi"
    fetch_file "cpanel/csf.tmpl" "$TMP_DIR/cpanel/csf.tmpl"
    fetch_file "csf/configserver.css" "$TMP_DIR/csf/configserver.css"
    fetch_file "BAHARI_VERSION" "$TMP_DIR/BAHARI_VERSION"
    fetch_file "BAHARI_CHANGELOG.md" "$TMP_DIR/BAHARI_CHANGELOG.md"
    SOURCE_DIR="$TMP_DIR"
}

timestamp="$(date +%Y%m%d%H%M%S)"

csf_exists() {
    command -v csf >/dev/null 2>&1 || [ -d /etc/csf ] || [ -d /usr/local/csf ]
}

is_bahari_csf() {
    [ -f /usr/local/csf/bahari_version.txt ] && return 0
    grep -q "BIT CSF Control" /usr/local/csf/lib/ConfigServer/DisplayUI.pm 2>/dev/null && return 0
    grep -q "BahariHost CSF Control" /usr/local/csf/lib/ConfigServer/DisplayUI.pm 2>/dev/null && return 0
    return 1
}

backup_existing_csf_tree() {
    local backup="/root/csf-before-bit-replace-$timestamp.tar.gz"
    local paths=()

    [ -e /etc/csf ] && paths+=("/etc/csf")
    [ -e /usr/local/csf ] && paths+=("/usr/local/csf")
    [ -e /usr/local/cpanel/whostmgr/docroot/cgi/configserver ] && paths+=("/usr/local/cpanel/whostmgr/docroot/cgi/configserver")
    [ -e /usr/local/cpanel/whostmgr/docroot/templates/csf.tmpl ] && paths+=("/usr/local/cpanel/whostmgr/docroot/templates/csf.tmpl")

    if [ "${#paths[@]}" -gt 0 ]; then
        tar -czf "$backup" "${paths[@]}" 2>/dev/null || true
        echo "Existing CSF backup: $backup"
    fi
}

remove_csf_package() {
    if command -v rpm >/dev/null 2>&1 && rpm -q cpanel-csf >/dev/null 2>&1; then
        echo "Removing existing cpanel-csf package..."
        if command -v dnf >/dev/null 2>&1; then
            dnf remove -y cpanel-csf
        elif command -v yum >/dev/null 2>&1; then
            yum remove -y cpanel-csf
        else
            rpm -e cpanel-csf || true
        fi
    elif command -v dpkg >/dev/null 2>&1 && dpkg -s cpanel-csf >/dev/null 2>&1; then
        echo "Removing existing cpanel-csf package..."
        apt remove -y cpanel-csf
    fi
}

move_leftover_csf_paths() {
    for path in /etc/csf /usr/local/csf /usr/local/cpanel/whostmgr/docroot/cgi/configserver; do
        if [ -e "$path" ]; then
            local dest="${path}.replaced-by-bit.$timestamp"
            echo "Moving leftover $path to $dest"
            mv "$path" "$dest"
        fi
    done
}

replace_foreign_csf() {
    if csf_exists && ! is_bahari_csf; then
        echo "Existing CSF detected, but BIT/BahariHost hardening marker was not found."
        echo "Backing up and replacing it with this hardened build..."
        backup_existing_csf_tree
        systemctl stop lfd 2>/dev/null || true
        systemctl stop csf 2>/dev/null || true
        remove_csf_package
        move_leftover_csf_paths
    fi
}

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

replace_foreign_csf
install_csf
prepare_sources

echo "Backing up current files..."
backup_file /etc/csf/csf.conf
backup_file /usr/local/csf/lib/ConfigServer/DisplayUI.pm
backup_file /usr/local/cpanel/whostmgr/docroot/cgi/configserver/csf.cgi
backup_file /usr/local/cpanel/whostmgr/docroot/templates/csf.tmpl
backup_file /usr/local/cpanel/whostmgr/docroot/cgi/configserver/csf/configserver.css

echo "Installing modified WHM UI files..."
mkdir -p /usr/local/csf/lib/ConfigServer
mkdir -p /usr/local/cpanel/whostmgr/docroot/cgi/configserver/csf
mkdir -p /usr/local/cpanel/whostmgr/docroot/templates
install -m 0644 "$SOURCE_DIR/lib/ConfigServer/DisplayUI.pm" /usr/local/csf/lib/ConfigServer/DisplayUI.pm
install -m 0700 "$SOURCE_DIR/cpanel/csf.cgi" /usr/local/cpanel/whostmgr/docroot/cgi/configserver/csf.cgi
install -m 0644 "$SOURCE_DIR/cpanel/csf.tmpl" /usr/local/cpanel/whostmgr/docroot/templates/csf.tmpl
install -m 0644 "$SOURCE_DIR/csf/configserver.css" /usr/local/cpanel/whostmgr/docroot/cgi/configserver/csf/configserver.css
install -m 0644 "$SOURCE_DIR/BAHARI_VERSION" /usr/local/csf/bahari_version.txt
install -m 0644 "$SOURCE_DIR/BAHARI_CHANGELOG.md" /usr/local/csf/bahari_changelog.md

echo "Applying CSF settings..."
set_csf_option TESTING "0"
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
