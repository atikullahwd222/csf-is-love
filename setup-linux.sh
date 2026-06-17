#!/usr/bin/env bash
set -euo pipefail

REPO_ARCHIVE_URL="${REPO_ARCHIVE_URL:-https://github.com/atikullahwd222/csf-is-love/archive/refs/heads/main.tar.gz}"
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

fix_perl_shebang() {
    local file="$1"
    if [ -f "$file" ]; then
        sed -i '1s|^#!.*perl.*$|#!/usr/bin/env perl|' "$file"
    fi
}

csf_install_looks_valid() {
    [ -x /usr/sbin/csf ] || return 1
    [ -x /usr/sbin/lfd ] || return 1
    [ -f /etc/csf/csf.conf ] || return 1
    ! head -n 1 /usr/sbin/csf 2>/dev/null | grep -q "/usr/local/cpanel/3rdparty/bin/perl" || return 1
    ! head -n 1 /usr/sbin/lfd 2>/dev/null | grep -q "/usr/local/cpanel/3rdparty/bin/perl" || return 1
    return 0
}

install_csf() {
    if csf_install_looks_valid; then
        echo "CSF already installed. Keeping current install and applying hardening."
        return
    fi

    echo "Installing CSF for plain Linux from GitHub source..."
    TMP_DIR="$(mktemp -d)"
    download_file "$REPO_ARCHIVE_URL" "$TMP_DIR/csf-source.tgz"
    tar -xzf "$TMP_DIR/csf-source.tgz" -C "$TMP_DIR"

    local source_dir
    source_dir="$(find "$TMP_DIR" -maxdepth 1 -type d -name 'csf-is-love-*' | head -n 1)"
    if [ ! -d "$source_dir" ]; then
        echo "ERROR: Unable to find extracted CSF source directory"
        exit 1
    fi

    backup_file /etc/csf
    backup_file /usr/local/csf
    backup_file /usr/sbin/csf
    backup_file /usr/sbin/lfd

    install -d -m 0700 /etc/csf
    install -d -m 0700 /var/lib/csf /var/lib/csf/backup /var/lib/csf/Geo /var/lib/csf/stats /var/lib/csf/lock /var/lib/csf/zone
    install -d -m 0755 /usr/local/csf /usr/local/csf/bin /usr/local/csf/lib /usr/local/csf/tpl /usr/local/csf/profiles /usr/local/csf/docs /usr/local/csf/data /usr/local/csf/messenger /usr/local/csf/cron
    install -d -m 0755 /usr/sbin /etc/cron.d /etc/logrotate.d /usr/local/man/man1

    install -m 0700 "$source_dir/csf.pl" /usr/sbin/csf
    install -m 0700 "$source_dir/lfd.pl" /usr/sbin/lfd

    install -m 0700 "$source_dir/bin/csftest.pl" /usr/local/csf/bin/
    install -m 0700 "$source_dir/bin/pt_deleted_action.pl" /usr/local/csf/bin/
    install -m 0700 "$source_dir/bin/regex.custom.pm" /usr/local/csf/bin/
    install -m 0700 "$source_dir/bin/remove_apf_bfd.sh" /usr/local/csf/bin/
    install -m 0700 "$source_dir/bin/auto.pl" /usr/local/csf/bin/
    fix_perl_shebang /usr/sbin/csf
    fix_perl_shebang /usr/sbin/lfd
    fix_perl_shebang /usr/local/csf/bin/csftest.pl
    fix_perl_shebang /usr/local/csf/bin/pt_deleted_action.pl
    fix_perl_shebang /usr/local/csf/bin/regex.custom.pm
    fix_perl_shebang /usr/local/csf/bin/auto.pl

    cp -a "$source_dir/lib/." /usr/local/csf/lib/
    cp -a "$source_dir/tpl/." /usr/local/csf/tpl/
    cp -a "$source_dir/profiles/." /usr/local/csf/profiles/
    cp -a "$source_dir/etc/messenger/." /usr/local/csf/messenger/

    install -m 0644 "$source_dir/LICENSE.txt" /usr/local/csf/docs/license.txt
    install -m 0644 "$source_dir/etc/changelog.txt" /usr/local/csf/docs/
    install -m 0644 "$source_dir/etc/readme.txt" /usr/local/csf/docs/
    install -m 0644 "$source_dir/etc/version.txt" /usr/local/csf/docs/

    install -m 0644 "$source_dir/etc/cpanel.allow" /usr/local/csf/data/
    install -m 0644 "$source_dir/etc/cpanel.comodo.allow" /usr/local/csf/data/
    install -m 0644 "$source_dir/etc/cpanel.comodo.ignore" /usr/local/csf/data/
    install -m 0644 "$source_dir/etc/cpanel.ignore" /usr/local/csf/data/
    install -m 0644 "$source_dir/etc/csf.cloudflare" /usr/local/csf/data/

    for file in csf.allow csf.blocklists csf.conf csf.deny csf.dirwatch csf.dyndns csf.fignore csf.ignore csf.logfiles csf.logignore csf.mignore csf.pignore csf.rblconf csf.redirect csf.resellers csf.rignore csf.signore csf.sips csf.smtpauth csf.suignore csf.syslogs csf.syslogusers csf.uidignore; do
        if [ ! -e "/etc/csf/$file" ]; then
            install -m 0644 "$source_dir/etc/$file" "/etc/csf/$file"
        fi
    done

    install -m 0600 "$source_dir/etc/csf.conf" /usr/local/csf/profiles/reset_to_defaults.conf
    install -m 0644 "$source_dir/csfcron.sh" /usr/local/csf/cron/csf-cron
    install -m 0644 "$source_dir/lfdcron.sh" /usr/local/csf/cron/lfd-cron
    install -m 0644 "$source_dir/lfd.logrotate" /etc/logrotate.d/lfd
    install -m 0644 "$source_dir/csf.1.txt" /usr/local/man/man1/csf.1

    if [ -d /usr/lib/systemd/system ]; then
        install -m 0644 "$source_dir/csf.service" /usr/lib/systemd/system/
        install -m 0644 "$source_dir/lfd.service" /usr/lib/systemd/system/
        systemctl daemon-reload || true
    elif [ -d /lib/systemd/system ]; then
        install -m 0644 "$source_dir/csf.service" /lib/systemd/system/
        install -m 0644 "$source_dir/lfd.service" /lib/systemd/system/
        systemctl daemon-reload || true
    fi

    ln -sf /usr/sbin/csf /etc/csf/csf.pl
    ln -sf /usr/sbin/lfd /etc/csf/lfd.pl
    ln -sf /usr/local/csf/bin/csftest.pl /etc/csf/csftest.pl
    ln -sf /usr/local/csf/bin/pt_deleted_action.pl /etc/csf/pt_deleted_action.pl
    ln -sf /usr/local/csf/bin/remove_apf_bfd.sh /etc/csf/remove_apf_bfd.sh
    ln -sf /usr/local/csf/bin/regex.custom.pm /etc/csf/regex.custom.pm
    ln -sfn /usr/local/csf/tpl /etc/csf/alerts
    ln -sf /usr/local/csf/docs/changelog.txt /etc/csf/changelog.txt
    ln -sf /usr/local/csf/docs/license.txt /etc/csf/license.txt
    ln -sf /usr/local/csf/docs/readme.txt /etc/csf/readme.txt
    ln -sf /usr/local/csf/docs/version.txt /etc/csf/version.txt
    ln -sf /usr/local/csf/data/cpanel.allow /etc/csf/cpanel.allow
    ln -sf /usr/local/csf/data/cpanel.comodo.allow /etc/csf/cpanel.comodo.allow
    ln -sf /usr/local/csf/data/cpanel.comodo.ignore /etc/csf/cpanel.comodo.ignore
    ln -sf /usr/local/csf/data/cpanel.ignore /etc/csf/cpanel.ignore
    ln -sf /usr/local/csf/data/csf.cloudflare /etc/csf/csf.cloudflare
    ln -sfn /usr/local/csf/messenger /etc/csf/messenger
    ln -sf /usr/local/csf/cron/csf-cron /etc/cron.d/csf-cron
    ln -sf /usr/local/csf/cron/lfd-cron /etc/cron.d/lfd-cron
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
