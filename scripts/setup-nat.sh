#!/usr/bin/env bash
set -euo pipefail

find_usb_iface() {
    ip -o link show | awk -F': ' '
        /usb|CDC|RNDIS|ecm|cdc_ether|enx/ { print $2; exit }
    '
}

find_default_out_iface() {
    ip route get 1.1.1.1 2>/dev/null | awk '
        {
            for (i=1; i<=NF; i++) {
                if ($i == "dev") {
                    print $(i+1)
                    exit
                }
            }
        }
    '
}

main() {
    echo "=== setup_nat.sh ==="
    local usb_iface
    usb_iface="$(find_usb_iface || true)"
    if [[ -z "${usb_iface}" ]]; then
        echo "No USB Ethernet interface detected; assuming usb0"
        usb_iface="usb0"
    else
        echo "Detected USB Ethernet interface: ${usb_iface}"
    fi

    local out_iface
    out_iface="$(find_default_out_iface || true)"
    if [[ -z "${out_iface}" ]]; then
        echo "Could not detect outbound interface"
        exit 1
    fi
    echo "Using outbound interface: ${out_iface}"

    sysctl -w net.ipv4.ip_forward=1

    iptables -t nat -D POSTROUTING -o "${out_iface}" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i "${usb_iface}" -o "${out_iface}" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "${out_iface}" -o "${usb_iface}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

    iptables -t nat -A POSTROUTING -o "${out_iface}" -j MASQUERADE
    iptables -A FORWARD -i "${usb_iface}" -o "${out_iface}" -j ACCEPT
    iptables -A FORWARD -i "${out_iface}" -o "${usb_iface}" -m state --state RELATED,ESTABLISHED -j ACCEPT

    echo "NAT enabled from ${usb_iface} to ${out_iface}"
}

main "$@"