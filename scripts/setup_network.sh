#!/usr/bin/env bash
set -euo pipefail

NETWORK_DIR="/etc/systemd/network"
LINK_FILE="${NETWORK_DIR}/10-usb0.link"
NETWORK_FILE="${NETWORK_DIR}/20-usb0.network"

find_usb_iface() {
    ip -o link show | awk -F': ' '
        /usb|CDC|RNDIS|ecm|cdc_ether|enx/ { print $2; exit }
    '
}

get_iface_mac() {
    local iface="$1"
    cat "/sys/class/net/${iface}/address" 2>/dev/null || true
}

cleanup_old_configs() {
    echo "Cleaning stale network config from ${NETWORK_DIR}"
    rm -f "${NETWORK_DIR}"/*eth0* "${NETWORK_DIR}"/*usb0* "${LINK_FILE}" "${NETWORK_FILE}"
}

write_link_file() {
    local mac="$1"
    cat > "${LINK_FILE}" <<EOF
[Match]
MACAddress=${mac}

[Link]
Name=usb0
EOF
}

write_network_file() {
    cat > "${NETWORK_FILE}" <<EOF
[Match]
Name=usb0

[Network]
DHCP=ipv4
EOF
}

main() {
    echo "=== setup_network.sh ==="
    local usb_iface
    usb_iface="$(find_usb_iface || true)"
    if [[ -z "${usb_iface}" ]]; then
        echo "No USB Ethernet interface detected, defaulting to usb0"
        usb_iface="usb0"
    else
        echo "Detected USB Ethernet interface: ${usb_iface}"
    fi

    local mac
    mac="$(get_iface_mac "${usb_iface}")"
    if [[ -z "${mac}" ]]; then
        echo "Could not read MAC address for ${usb_iface}, using generic USB match"
    else
        echo "Using MAC ${mac} for .link file"
    fi

    cleanup_old_configs

    if [[ -n "${mac}" ]]; then
        write_link_file "${mac}"
    else
        cat > "${LINK_FILE}" <<EOF
[Match]
Name=${usb_iface}

[Link]
Name=usb0
EOF
    fi

    write_network_file

    systemctl restart systemd-networkd
    ip link set dev usb0 up || true

    echo "Configured USB Ethernet on usb0 (detected: ${usb_iface})"
}

main "$@"