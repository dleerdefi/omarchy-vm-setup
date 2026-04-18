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

echo "==> Installing libvirt-docker-fix.service..."
cp "$SCRIPT_DIR/libvirt-docker-fix.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable libvirt-docker-fix.service

echo ""
echo "Done. IMPORTANT: log out and back in for group membership to take effect."
echo "Then verify with: groups $REALUSER"
echo ""
echo "After re-login, open virt-manager to create your first VM."
