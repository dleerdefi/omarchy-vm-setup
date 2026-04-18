# Omarchy VM Setup

KVM/libvirt virtual machine setup for Omarchy (Arch Linux) machines that also run Docker.

## The Problem

Docker and libvirt both manage firewall rules, and they conflict. Docker creates an
nftables `FORWARD` chain with `policy drop` — all forwarded traffic is blocked unless
explicitly allowed. libvirt puts its own forwarding and NAT rules in a separate nftables
table, but Docker's drop policy runs first and silently kills VM internet traffic.

The fix is a small systemd service (`libvirt-docker-fix.service`) that runs after both
Docker and libvirtd start, and adds the two rules needed to punch virbr0 traffic through
Docker's forward chain.

## Prerequisites

- Omarchy installed
- Docker installed and running (`systemctl is-active docker`)

## Setup

```bash
git clone https://github.com/dleerdefi/Omarchy-VM-Setup.git
cd Omarchy-VM-Setup
sudo bash setup.sh
```

Then **log out and back in** — the kvm and libvirt group memberships won't take effect
until you do.

## Verify

After re-login:

```bash
# Groups should include kvm and libvirt
groups $USER

# Services should be active/enabled
systemctl is-active libvirtd
systemctl is-enabled libvirt-docker-fix
```

## Where to put ISOs and disk images

libvirt runs VMs as the `qemu` user, which **cannot read files in your home directory**
(e.g. `~/Downloads`) due to default home permissions. Always put ISOs and qcow2 images
in libvirt's image pool:

```bash
sudo mv ~/Downloads/your-image.iso /var/lib/libvirt/images/
```

Otherwise you'll get "no bootable device" or permission errors.

## Creating a VM

Open virt-manager (`virt-manager` from a terminal, or search for "Virtual Machine Manager").

**Two common workflows:**

- **Installing from an ISO** (e.g. Ubuntu, Fedora, Arch installer)
  → `File → New Virtual Machine → Local install media` → browse to your ISO

- **Booting a pre-built qcow2 image** (e.g. Fedora Cloud, Parrot, Kali, Debian cloud images)
  → `File → New Virtual Machine → Import existing disk image` → browse to your qcow2

Set RAM (4096+ MB) and vCPUs (2+), then finish. The default NAT network gives VMs
internet via `192.168.122.0/24`.

### qcow2 images: UEFI firmware required

Most modern pre-built qcow2 images (Parrot, Kali, Fedora Cloud, Ubuntu Cloud) are
**UEFI-only** — they have no BIOS bootloader. Before clicking Finish in virt-manager,
check **"Customize configuration before install"**, then in the Overview panel set:

- **Firmware:** `UEFI x86_64: .../OVMF_CODE.fd` (pick the one **without** `secboot`)
- **Chipset:** `Q35`

Firmware and chipset are locked after VM creation — you'd have to delete and recreate
the VM to change them, so get it right the first time.

### Distributions that ship as archives

Some distros (notably Kali) package their qcow2 inside a `.7z` archive. Extract first:

```bash
sudo pacman -S --needed p7zip
cd ~/Downloads
7z x kali-linux-*-qemu-amd64.7z
sudo mv kali-linux-*/*.qcow2 /var/lib/libvirt/images/
```

### CLI alternative (ISO install)

```bash
virt-install \
  --name my-vm \
  --ram 4096 \
  --vcpus 2 \
  --disk size=40 \
  --cdrom /var/lib/libvirt/images/your-image.iso \
  --os-variant detect=on \
  --network network=default \
  --graphics spice
```

## Persistence

VMs and their state persist across host reboots automatically:

- `libvirtd` and the default NAT network start on boot
- `libvirt-docker-fix.service` re-applies the nftables fix on every boot
- Changes inside a VM are saved to its qcow2 on shutdown

**Optional — auto-start a VM when your host boots:**

```bash
sudo virsh autostart my-vm         # enable
sudo virsh list --autostart        # verify
sudo virsh autostart --disable my-vm  # disable
```

## SSH into VMs (optional)

Standard SSH works over the default NAT network (`ssh user@192.168.122.x`). For
cross-machine access, you can also install Tailscale inside each VM:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Approve it at the auth URL, then SSH to it by Tailscale IP from any machine in the network.

## How the fix works

`libvirt-docker-fix.service` runs once after Docker and libvirtd start and adds:

```
nft add rule ip filter DOCKER-USER iifname "virbr0" accept
nft add rule ip filter DOCKER-USER oifname "virbr0" ct state established,related accept
```

`DOCKER-USER` is Docker's dedicated chain for user-defined rules — Docker never flushes
it on restart, so these rules persist across Docker restarts. The service re-applies them
on every system boot.
