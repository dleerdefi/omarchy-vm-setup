#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0"
    exit 1
fi

REALUSER="${SUDO_USER:-$USER}"

if ! grep -qE 'vmx|svm' /proc/cpuinfo; then
    echo "ERROR: CPU does not support hardware virtualization (vmx/svm)."
    echo "Enable Intel VT-x or AMD-V in BIOS."
    exit 1
fi

echo "==> Installing packages..."
pacman -S --needed --noconfirm \
    libvirt libvirt-python virt-manager virt-install virtiofsd \
    qemu-desktop edk2-ovmf spice spice-gtk virglrenderer dnsmasq

echo "==> Adding $REALUSER to kvm and libvirt groups..."
usermod -aG kvm,libvirt "$REALUSER"

echo "==> Enabling libvirt services..."
systemctl enable --now libvirtd.service
systemctl enable libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket
systemctl enable virtlogd.service

echo "==> Starting default NAT network..."
virsh net-start default 2>/dev/null || true
virsh net-autostart default

if command -v ufw >/dev/null 2>&1; then
    # Omarchy 4 (Quattro) manages the firewall with ufw and ufw-docker. ufw-docker owns
    # DOCKER-USER and ends it with a RETURN, so rules appended there never match, and
    # ufw's default deny blocks the VMs' DHCP/DNS requests to libvirt's dnsmasq.
    # Allow virbr0 in ufw instead: DOCKER-USER jumps to ufw-user-forward first.
    echo "==> Allowing libvirt's virbr0 through ufw..."
    ufw allow in on virbr0 to any port 67 proto udp comment 'libvirt DHCP'
    ufw allow in on virbr0 to any port 53 comment 'libvirt DNS'
    ufw route allow in on virbr0 comment 'libvirt VMs out'
    ufw route allow out on virbr0 comment 'libvirt VMs return'

    if systemctl is-enabled --quiet libvirt-docker-fix.service 2>/dev/null; then
        echo "==> Retiring libvirt-docker-fix.service (superseded by the ufw rules)..."
        systemctl disable libvirt-docker-fix.service
    fi
else
    echo "==> Installing libvirt-docker-fix.service..."
    cp "$SCRIPT_DIR/libvirt-docker-fix.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable libvirt-docker-fix.service
fi

echo ""
echo "Done. IMPORTANT: log out and back in for group membership to take effect."
echo "Then verify with: groups $REALUSER"
echo ""
echo "After re-login, open virt-manager to create your first VM."
