#!/usr/bin/env bash
# qemu-archstrap-image-rpi5
# RPi5 / CM5 Exaviz carrier — btrfs @boot @/ @swap dracut dropbear UEFI GRUB
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info() { echo -e "${CYAN}[rpi5-image]${NC} $*"; }
ok()   { echo -e "${GREEN}[  OK  ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ WARN ]${NC} $*"; }
die()  { echo -e "${RED}[ FAIL ]${NC} $*" >&2; exit 1; }

# ── Config ────────────────────────────────────────────────────────────────────
IMG="${1:-rpi5-arch.img}"
IMG_SIZE="${2:-16G}"
SWAP_SIZE="${3:-4G}"            # swap.img inside @swap subvolume
MOUNT_ROOT="/mnt/rpi5-root"
HOSTNAME="archlinux-cm5"
RPI5_UEFI_VER="v0.3"
RPI5_UEFI_URL="https://github.com/worproject/rpi5-uefi/releases/download/${RPI5_UEFI_VER}/RPi5_UEFI_Firmware_${RPI5_UEFI_VER}.zip"
LOOP_DEV=""

# Dropbear authorized_keys — set this or pass via env
DROPBEAR_AUTHKEYS="${DROPBEAR_AUTHKEYS:-$HOME/.ssh/id_ed25519.pub}"

# ── Cleanup ───────────────────────────────────────────────────────────────────
cleanup() {
    info "Unmounting..."
    for mp in proc sys dev/pts dev run; do
        umount -l "${MOUNT_ROOT}/${mp}" 2>/dev/null || true
    done
    # unmount btrfs subvolume mounts in reverse
    umount -l "${MOUNT_ROOT}/boot"      2>/dev/null || true
    umount -l "${MOUNT_ROOT}/swap"      2>/dev/null || true
    umount -l "${MOUNT_ROOT}/.snapshots" 2>/dev/null || true
    umount -l "${MOUNT_ROOT}/var/log"   2>/dev/null || true
    umount -l "${MOUNT_ROOT}/boot/efi"  2>/dev/null || true
    umount -l "$MOUNT_ROOT"             2>/dev/null || true
    [[ -n "$LOOP_DEV" ]] && losetup -d "$LOOP_DEV" 2>/dev/null || true
    ok "Done"
}
trap cleanup EXIT

[[ $EUID -ne 0 ]] && die "Must run as root"

for cmd in parted mkfs.fat mkfs.btrfs losetup btrfs wget unzip \
           arch-chroot pacstrap; do
    command -v "$cmd" &>/dev/null || die "Missing dependency: $cmd"
done

# ── Create + partition image ──────────────────────────────────────────────────
info "Creating ${IMG_SIZE} image: ${IMG}"
truncate -s "$IMG_SIZE" "$IMG"

parted -s "$IMG" \
    mklabel gpt \
    mkpart ESP  fat32  1MiB    257MiB \
    set 1 esp on \
    mkpart ROOT btrfs  257MiB  100%

LOOP_DEV=$(losetup --find --partscan --show "$IMG")
ok "Loop: $LOOP_DEV"

ESP_DEV="${LOOP_DEV}p1"
ROOT_DEV="${LOOP_DEV}p2"

ESP_UUID=$(blkid  -s UUID -o value "$ESP_DEV")
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")

# ── Format ────────────────────────────────────────────────────────────────────
info "Formatting ESP FAT32..."
mkfs.fat -F32 -n "RPI5-EFI" "$ESP_DEV"

info "Formatting ROOT btrfs..."
mkfs.btrfs -L "ARCH-ROOT" -f "$ROOT_DEV"

# ── Create btrfs subvolumes ───────────────────────────────────────────────────
info "Creating btrfs subvolumes..."
BTRFS_TMP=$(mktemp -d)
mount -o compress=zstd "$ROOT_DEV" "$BTRFS_TMP"

btrfs subvolume create "${BTRFS_TMP}/@"
btrfs subvolume create "${BTRFS_TMP}/@boot"
btrfs subvolume create "${BTRFS_TMP}/@swap"
btrfs subvolume create "${BTRFS_TMP}/@snapshots"
btrfs subvolume create "${BTRFS_TMP}/@var_log"
btrfs subvolume create "${BTRFS_TMP}/@home"

ok "Subvolumes: @ @boot @swap @snapshots @var_log @home"
umount "$BTRFS_TMP"
rmdir  "$BTRFS_TMP"

# ── Mount subvolumes ──────────────────────────────────────────────────────────
BTRFS_OPTS="compress=zstd,space_cache=v2,noatime"

info "Mounting subvolumes..."
mkdir -p "$MOUNT_ROOT"
mount -o "${BTRFS_OPTS},subvol=@"          "$ROOT_DEV" "$MOUNT_ROOT"

mkdir -p "${MOUNT_ROOT}"/{boot,swap,.snapshots,var/log,home,boot/efi}

mount -o "${BTRFS_OPTS},subvol=@boot"      "$ROOT_DEV" "${MOUNT_ROOT}/boot"
mount -o "${BTRFS_OPTS},subvol=@swap"      "$ROOT_DEV" "${MOUNT_ROOT}/swap"
mount -o "${BTRFS_OPTS},subvol=@snapshots" "$ROOT_DEV" "${MOUNT_ROOT}/.snapshots"
mount -o "${BTRFS_OPTS},subvol=@var_log"   "$ROOT_DEV" "${MOUNT_ROOT}/var/log"
mount -o "${BTRFS_OPTS},subvol=@home"      "$ROOT_DEV" "${MOUNT_ROOT}/home"
mount "$ESP_DEV" "${MOUNT_ROOT}/boot/efi"

ok "All subvolumes mounted"

# ── swap.img — disable CoW on @swap ──────────────────────────────────────────
# btrfs swap.img requires nodatacow on the subvolume
# We set it on the directory before creating the file
chattr +C "${MOUNT_ROOT}/swap" 2>/dev/null || \
    warn "chattr +C failed — swap.img may have CoW issues; set nodatacow mount option"

info "Creating swap.img (${SWAP_SIZE})..."
truncate -s "$SWAP_SIZE" "${MOUNT_ROOT}/swap/swap.img"
chmod 600 "${MOUNT_ROOT}/swap/swap.img"
mkswap "${MOUNT_ROOT}/swap/swap.img"
ok "swap.img ready"

# ── Bootstrap ─────────────────────────────────────────────────────────────────
info "Bootstrapping Arch aarch64..."
[[ ! -f /usr/bin/qemu-aarch64-static ]] && die "qemu-aarch64-static not found"
cp /usr/bin/qemu-aarch64-static "${MOUNT_ROOT}/usr/bin/" 2>/dev/null || \
    { mkdir -p "${MOUNT_ROOT}/usr/bin"; cp /usr/bin/qemu-aarch64-static "${MOUNT_ROOT}/usr/bin/"; }

pacstrap -C /etc/qemu-archstrap/pacman-aarch64.conf -K "$MOUNT_ROOT" \
    base base-devel \
    linux-rpi linux-rpi-headers linux-firmware \
    btrfs-progs \
    grub efibootmgr \
    dracut \
    dropbear \
    networkmanager \
    openssh \
    sudo \
    rpi-eeprom \
    snapper \
    vim \
    curl wget git

# ── fstab ─────────────────────────────────────────────────────────────────────
info "Writing fstab..."
cat > "${MOUNT_ROOT}/etc/fstab" <<EOF
# qemu-archstrap rpi5/cm5 btrfs image
# <device>                                  <mountpoint>   <type>  <options>                               <dump> <pass>

UUID=${ROOT_UUID}  /              btrfs   ${BTRFS_OPTS},subvol=@           0  0
UUID=${ROOT_UUID}  /boot          btrfs   ${BTRFS_OPTS},subvol=@boot       0  0
UUID=${ROOT_UUID}  /swap          btrfs   ${BTRFS_OPTS},subvol=@swap,nodatacow  0  0
UUID=${ROOT_UUID}  /.snapshots    btrfs   ${BTRFS_OPTS},subvol=@snapshots  0  0
UUID=${ROOT_UUID}  /var/log       btrfs   ${BTRFS_OPTS},subvol=@var_log    0  0
UUID=${ROOT_UUID}  /home          btrfs   ${BTRFS_OPTS},subvol=@home       0  0
UUID=${ESP_UUID}   /boot/efi      vfat    umask=0077                       0  2

# swap
/swap/swap.img     none           swap    sw                               0  0
EOF
ok "fstab written"

# ── Bind virtual filesystems ──────────────────────────────────────────────────
for mp in proc sys dev dev/pts run; do
    mkdir -p "${MOUNT_ROOT}/${mp}"
    mount --bind "/${mp}" "${MOUNT_ROOT}/${mp}"
done

# ── Hostname / locale / timezone ──────────────────────────────────────────────
echo "$HOSTNAME" > "${MOUNT_ROOT}/etc/hostname"
cat > "${MOUNT_ROOT}/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.local  ${HOSTNAME}
EOF

arch-chroot "$MOUNT_ROOT" ln -sf /usr/share/zoneinfo/UTC /etc/localtime
arch-chroot "$MOUNT_ROOT" hwclock --systohc 2>/dev/null || true
echo "en_US.UTF-8 UTF-8" >> "${MOUNT_ROOT}/etc/locale.gen"
arch-chroot "$MOUNT_ROOT" locale-gen
echo "LANG=en_US.UTF-8" > "${MOUNT_ROOT}/etc/locale.conf"

# ── dracut config ─────────────────────────────────────────────────────────────
info "Configuring dracut..."
mkdir -p "${MOUNT_ROOT}/etc/dracut.conf.d"

cat > "${MOUNT_ROOT}/etc/dracut.conf.d/rpi5.conf" <<'EOF'
# dracut config for RPi5 / CM5 btrfs + dropbear early SSH
hostonly="yes"
hostonly_cmdline="yes"
compress="zstd"

# btrfs root
add_dracutmodules+=" btrfs "
filesystems+=" btrfs "

# early SSH via dropbear for headless rescue
add_dracutmodules+=" dropbear "
dropbear_acl="/etc/dropbear/authorized_keys"
dropbear_rsa_key="/etc/dropbear/dropbear_rsa_host_key"
dropbear_ecdsa_key="/etc/dropbear/dropbear_ecdsa_host_key"
# IP config: dhcp on eth0 — adjust for CM5 Exaviz carrier NIC
kernel_cmdline="ip=dhcp"

# aarch64 / RPi specifics
add_drivers+=" broadcom vc4 drm "

# useful for headless debug
add_dracutmodules+=" network "
EOF
ok "dracut config written"

# ── dropbear host keys + authorized_keys ──────────────────────────────────────
info "Setting up dropbear..."
mkdir -p "${MOUNT_ROOT}/etc/dropbear"

# Generate host keys inside chroot
arch-chroot "$MOUNT_ROOT" dropbearkey -t rsa   -f /etc/dropbear/dropbear_rsa_host_key   -s 4096
arch-chroot "$MOUNT_ROOT" dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key

# Inject authorized_keys for early SSH login
if [[ -f "$DROPBEAR_AUTHKEYS" ]]; then
    cp "$DROPBEAR_AUTHKEYS" "${MOUNT_ROOT}/etc/dropbear/authorized_keys"
    chmod 600 "${MOUNT_ROOT}/etc/dropbear/authorized_keys"
    ok "authorized_keys injected from ${DROPBEAR_AUTHKEYS}"
else
    warn "No authorized_keys found at ${DROPBEAR_AUTHKEYS}"
    warn "Set DROPBEAR_AUTHKEYS=/path/to/pubkey.pub before running"
    warn "Early SSH rescue will not work without authorized_keys"
    touch "${MOUNT_ROOT}/etc/dropbear/authorized_keys"
fi

# ── dracut initramfs ──────────────────────────────────────────────────────────
info "Building initramfs with dracut..."
KERNEL_VER=$(ls "${MOUNT_ROOT}/lib/modules/" | head -1)
info "Kernel version detected: ${KERNEL_VER}"

arch-chroot "$MOUNT_ROOT" dracut \
    --force \
    --kver "$KERNEL_VER" \
    --add "btrfs dropbear network" \
    "/boot/initramfs-${KERNEL_VER}.img"

# fallback without hostonly
arch-chroot "$MOUNT_ROOT" dracut \
    --force \
    --no-hostonly \
    --kver "$KERNEL_VER" \
    --add "btrfs dropbear network" \
    "/boot/initramfs-${KERNEL_VER}-fallback.img"

ok "initramfs built"

# ── RPi5 UEFI firmware ────────────────────────────────────────────────────────
info "Downloading RPi5 UEFI firmware..."
UEFI_TMP=$(mktemp -d)
wget -q --show-progress "$RPI5_UEFI_URL" -O "${UEFI_TMP}/rpi5-uefi.zip" \
    || die "UEFI firmware download failed"
unzip -q "${UEFI_TMP}/rpi5-uefi.zip" -d "${UEFI_TMP}/uefi"

ESP="${MOUNT_ROOT}/boot/efi"
cp "${UEFI_TMP}/uefi/RPI_EFI.fd"  "$ESP/"
cp "${UEFI_TMP}/uefi/"*.dat        "$ESP/" 2>/dev/null || true
cp "${UEFI_TMP}/uefi/"*.elf        "$ESP/" 2>/dev/null || true

# config.txt for RPi5 UEFI mode
cat > "${ESP}/config.txt" <<'EOF'
# RPi5 / CM5 UEFI config
arm_64bit=1
enable_uart=1
uart_2ndstage=1
# CM5 Exaviz carrier — PCIe/SATA will enumerate after UEFI handoff
dtparam=pciex1=on
# Uncomment if using NVMe on CM5:
# dtparam=nvme=on
gpu_mem=16
EOF
ok "RPi5 UEFI firmware deployed"

# ── GRUB EFI install ──────────────────────────────────────────────────────────
info "Installing GRUB (arm64-efi)..."
arch-chroot "$MOUNT_ROOT" grub-install \
    --target=arm64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=ARCH \
    --removable \
    --recheck

# ── GRUB config ───────────────────────────────────────────────────────────────
info "Writing grub.cfg..."
KERNEL_IMG=$(ls "${MOUNT_ROOT}/boot/" | grep -E "^Image|^vmlinuz" | head -1)
INITRD_IMG="initramfs-${KERNEL_VER}.img"
INITRD_FBK="initramfs-${KERNEL_VER}-fallback.img"

# dracut uses rd.* kernel args; btrfs root needs rootflags for subvol
cat > "${MOUNT_ROOT}/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5
set timeout_style=menu

# RPi5 / CM5 Exaviz — Arch Linux aarch64 btrfs

menuentry "Arch Linux RPi5 (btrfs @)" {
    linux   /boot/${KERNEL_IMG} \\
            root=UUID=${ROOT_UUID} \\
            rootfstype=btrfs \\
            rootflags=subvol=@ \\
            rw \\
            rd.luks=0 \\
            rd.md=0 \\
            rd.dm=0 \\
            ip=dhcp \\
            console=ttyAMA0,115200 \\
            console=tty1 \\
            quiet
    initrd  /boot/${INITRD_IMG}
}

menuentry "Arch Linux RPi5 - Fallback initrd" {
    linux   /boot/${KERNEL_IMG} \\
            root=UUID=${ROOT_UUID} \\
            rootfstype=btrfs \\
            rootflags=subvol=@ \\
            rw \\
            rd.luks=0 \\
            ip=dhcp \\
            console=ttyAMA0,115200 \\
            console=tty1
    initrd  /boot/${INITRD_FBK}
}

menuentry "UEFI Firmware Settings" {
    fwsetup
}
EOF
ok "grub.cfg written"

# ── snapper config ────────────────────────────────────────────────────────────
info "Configuring snapper for @ subvolume..."
arch-chroot "$MOUNT_ROOT" snapper -c root create-config /
# timeline snapshots — edit to taste
cat > "${MOUNT_ROOT}/etc/snapper/configs/root" <<'EOF'
SUBVOLUME="/"
FSTYPE="btrfs"
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_LIMIT_HOURLY="6"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="6"
TIMELINE_LIMIT_YEARLY="2"
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
EOF
arch-chroot "$MOUNT_ROOT" systemctl enable snapper-timeline.timer snapper-cleanup.timer

# ── Enable services ───────────────────────────────────────────────────────────
info "Enabling services..."
arch-chroot "$MOUNT_ROOT" systemctl enable \
    NetworkManager \
    sshd \
    fstrim.timer   # periodic TRIM for eMMC/NVMe health on CM5

# ── CM5 / Exaviz carrier notes injected into image ───────────────────────────
mkdir -p "${MOUNT_ROOT}/etc/qemu-archstrap"
cat > "${MOUNT_ROOT}/etc/qemu-archstrap/cm5-exaviz-notes.txt" <<'EOF'
CM5 Exaviz Carrier — Post-boot checklist
─────────────────────────────────────────
PCIe / SATA:
  dtparam=pciex1=on in config.txt enables PCIe x1
  SATA via ASM1061 or similar bridge on Exaviz — should enumerate as /dev/sdX
  For eMMC sync / snapshot replication:
    btrfs send/receive @ or @snapshots to SATA target
    see: btrfs-send-snapshot-sync.sh (add to /usr/local/bin)

Snapshot sync to SATA (once disk attached):
  btrfs subvolume snapshot -r / /.snapshots/initial
  btrfs send /.snapshots/initial | btrfs receive /mnt/sata-backup/

Early SSH (dropbear in initramfs):
  ssh -p 222 root@<device-ip>      # dracut dropbear default port 222
  Useful for: LUKS unlock, rescue, pre-mount diagnostics

NVMe (CM5 M.2):
  dtparam=nvme=on in /boot/efi/config.txt
  After boot: btrfs device add /dev/nvme0n1 /   (add to btrfs pool)
              btrfs balance start -dconvert=raid1 /  (mirror eMMC+NVMe)

UART console:
  ttyAMA0 @ 115200 — always keep in kernel cmdline during bring-up
  Exaviz carrier exposes UART on debug header

UEFI firmware updates:
  rpi-eeprom-update -a    (updates pieeprom, not RPI_EFI.fd)
  RPI_EFI.fd updates: replace on ESP manually from worproject/rpi5-uefi releases
EOF
ok "CM5 Exaviz notes written to /etc/qemu-archstrap/cm5-exaviz-notes.txt"

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -f "${MOUNT_ROOT}/usr/bin/qemu-aarch64-static"
rm -rf "$UEFI_TMP"
warn "Root password not set — enter chroot and run: passwd"

echo ""
echo -e "${BOLD}${GREEN}── CM5/RPi5 Image Ready ──────────────────────────────────────────${NC}"
echo -e "  Image       : ${CYAN}${IMG}${NC}  (${IMG_SIZE})"
echo -e "  Btrfs layout: ${CYAN}@ @boot @swap @snapshots @var_log @home${NC}"
echo -e "  Swap        : ${CYAN}/swap/swap.img${NC}  (${SWAP_SIZE})"
echo -e "  Boot chain  : ${CYAN}RPi EEPROM → RPI_EFI.fd → grubaa64.efi → linux-rpi${NC}"
echo -e "  Initramfs   : ${CYAN}dracut + btrfs + dropbear${NC}"
echo -e "  Early SSH   : ${CYAN}ssh -p 222 root@<ip>${NC}  (set authorized_keys first)"
echo ""
echo -e "  Flash:"
echo -e "    ${YELLOW}dd if=${IMG} of=/dev/sdX bs=4M status=progress conv=fsync${NC}"
echo -e "    ${YELLOW}bmaptool copy ${IMG} /dev/sdX${NC}   # faster if available"
echo ""
echo -e "  Re-enter chroot:"
echo -e "    ${YELLOW}mount -o ${BTRFS_OPTS},subvol=@ UUID=${ROOT_UUID} ${MOUNT_ROOT}${NC}"
echo -e "    ${YELLOW}mount -o ${BTRFS_OPTS},subvol=@boot UUID=${ROOT_UUID} ${MOUNT_ROOT}/boot${NC}"
echo -e "    ${YELLOW}mount UUID=${ESP_UUID} ${MOUNT_ROOT}/boot/efi${NC}"
echo -e "    ${YELLOW}arch-chroot ${MOUNT_ROOT}${NC}"
echo -e "${GREEN}──────────────────────────────────────────────────────────────────${NC}"
