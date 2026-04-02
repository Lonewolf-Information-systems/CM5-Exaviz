#!/usr/bin/env bash
# qemu-archstrap-image-rpi5
# RPi5 / CM5 Exaviz Cruiser — btrfs @boot @/ @swap dracut dropbear UEFI GRUB
# UEFI: https://github.com/NumberOneGit/rpi5-uefi  (active fork)
# CM5 PKGBUILDs: https://github.com/Lonewolf-Information-systems/CM5-Exaviz
# Source: https://github.com/Lonewolf-Information-systems/CM5-Exaviz/tree/main/Arch-Linux
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
SWAP_SIZE="${3:-4G}"
MOUNT_ROOT="/mnt/rpi5-root"
HOSTNAME="archlinux-cm5"
LOOP_DEV=""
UEFI_TMP=""

# Active rpi5-uefi fork — NumberOneGit
# Check https://github.com/NumberOneGit/rpi5-uefi/releases for latest
RPI5_UEFI_VER="${RPI5_UEFI_VER:-v0.3}"
RPI5_UEFI_BASE="https://github.com/NumberOneGit/rpi5-uefi/releases/download"
RPI5_UEFI_URL="${RPI5_UEFI_BASE}/${RPI5_UEFI_VER}/RPi5_UEFI_Firmware_${RPI5_UEFI_VER}.zip"

# Lonewolf CM5-Exaviz Arch Linux resources
LONEWOLF_BASE="https://raw.githubusercontent.com/Lonewolf-Information-systems/CM5-Exaviz/main/Arch-Linux"
LONEWOLF_PKGBUILD_BASE="https://github.com/Lonewolf-Information-systems/CM5-Exaviz/raw/main/Arch-Linux/rpi5-uefi-cm5"

# arch-install-scripts (pacstrap/arch-chroot)
ARCH_INSTALL_SCRIPTS="https://github.com/archlinux/arch-install-scripts.git"

DROPBEAR_AUTHKEYS="${DROPBEAR_AUTHKEYS:-$HOME/.ssh/id_ed25519.pub}"
BTRFS_OPTS="compress=zstd,space_cache=v2,noatime"

# ── Cleanup ───────────────────────────────────────────────────────────────────
cleanup() {
    info "Unmounting..."
    for mp in proc sys dev/pts dev run; do
        umount -l "${MOUNT_ROOT}/${mp}" 2>/dev/null || true
    done
    umount -l "${MOUNT_ROOT}/boot/efi"   2>/dev/null || true
    umount -l "${MOUNT_ROOT}/boot"       2>/dev/null || true
    umount -l "${MOUNT_ROOT}/swap"       2>/dev/null || true
    umount -l "${MOUNT_ROOT}/.snapshots" 2>/dev/null || true
    umount -l "${MOUNT_ROOT}/var/log"    2>/dev/null || true
    umount -l "${MOUNT_ROOT}/home"       2>/dev/null || true
    umount -l "$MOUNT_ROOT"              2>/dev/null || true
    [[ -n "$LOOP_DEV"  ]] && losetup -d "$LOOP_DEV"   2>/dev/null || true
    [[ -n "$UEFI_TMP"  ]] && rm -rf "$UEFI_TMP"
    ok "Cleanup done"
}
trap cleanup EXIT

[[ $EUID -ne 0 ]] && die "Must run as root"

for cmd in parted mkfs.fat mkfs.btrfs losetup btrfs wget unzip \
           arch-chroot pacstrap git; do
    command -v "$cmd" &>/dev/null || die "Missing dependency: $cmd"
done

# ── Fetch + validate Lonewolf CM5 PKGBUILDs ──────────────────────────────────
fetch_lonewolf_pkgbuilds() {
    local destdir="${MOUNT_ROOT}/usr/local/src/CM5-Exaviz"
    info "Fetching Lonewolf CM5-Exaviz PKGBUILDs..."
    mkdir -p "$destdir"

    # Shallow clone — we want the PKGBUILDs, not full history
    git clone --depth=1 \
        https://github.com/Lonewolf-Information-systems/CM5-Exaviz.git \
        "$destdir" 2>/dev/null \
        && ok "CM5-Exaviz repo cloned → ${destdir}" \
        || warn "Could not clone CM5-Exaviz repo — continuing without"

    # Validate PKGBUILDs if namcap available on host
    if command -v namcap &>/dev/null; then
        info "Running namcap on CM5-Exaviz PKGBUILDs..."
        find "$destdir" -name "PKGBUILD" | while read -r pb; do
            echo "  namcap: $pb"
            namcap "$pb" 2>&1 | sed 's/^/    /' || true
        done
    else
        warn "namcap not on host — skipping PKGBUILD lint"
        warn "Install namcap for validation: pacman -S namcap"
    fi

    # Extract rpi5-uefi-cm5 PKGBUILD for reference
    local cm5_pkgbuild="${destdir}/Arch-Linux/rpi5-uefi-cm5/PKGBUILD"
    if [[ -f "$cm5_pkgbuild" ]]; then
        ok "Found rpi5-uefi-cm5 PKGBUILD"
        # Extract pkgver for potential version sync
        local upstream_ver
        upstream_ver=$(bash -c "source ${cm5_pkgbuild}; echo \$pkgver" 2>/dev/null || true)
        [[ -n "$upstream_ver" ]] && \
            info "Lonewolf rpi5-uefi-cm5 pkgver: ${upstream_ver}"
        # Cross-check against our UEFI_VER
        if [[ -n "$upstream_ver" ]] && \
           [[ "v${upstream_ver}" != "$RPI5_UEFI_VER" ]]; then
            warn "Version mismatch: script uses ${RPI5_UEFI_VER}, Lonewolf PKGBUILD has v${upstream_ver}"
            warn "Consider: RPI5_UEFI_VER=v${upstream_ver} $0 $*"
        fi
    fi
}

# ── deploy_config_txt ─────────────────────────────────────────────────────────
# Copy worproject/NumberOneGit config.txt from zip (authoritative base)
# then append Exaviz Cruiser CM5 fragment.
# Cross-reference Lonewolf PKGBUILD config fragment if available.
deploy_config_txt() {
    local esp="$1"
    local uefi_zip_dir="$2"

    [[ -f "${uefi_zip_dir}/config.txt" ]] || \
        die "config.txt not in UEFI zip — check NumberOneGit release contents"

    grep -q "armstub=RPI_EFI.fd" "${uefi_zip_dir}/config.txt" || \
        die "config.txt missing armstub=RPI_EFI.fd — wrong zip or corrupt download"

    info "Copying config.txt from NumberOneGit rpi5-uefi zip..."
    cp "${uefi_zip_dir}/config.txt" "${esp}/config.txt"

    # Check if Lonewolf repo has a config fragment to merge
    local lonewolf_cfg="${MOUNT_ROOT}/usr/local/src/CM5-Exaviz/Arch-Linux/rpi5-uefi-cm5/config.txt"
    if [[ -f "$lonewolf_cfg" ]]; then
        info "Merging Lonewolf CM5-Exaviz config fragment..."
        echo "" >> "${esp}/config.txt"
        echo "# ── Lonewolf CM5-Exaviz config fragment ──" >> "${esp}/config.txt"
        # Skip lines already present in base config to avoid duplicates
        while IFS= read -r line; do
            # skip comments, blanks, lines already in base
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]]           && continue
            local key="${line%%=*}"
            if ! grep -q "^${key}=" "${esp}/config.txt"; then
                echo "$line" >> "${esp}/config.txt"
            else
                info "  skipping duplicate: $line"
            fi
        done < "$lonewolf_cfg"
        ok "Lonewolf config fragment merged"
    fi

    info "Appending Exaviz Cruiser CM5 additions..."
    cat >> "${esp}/config.txt" <<'EXAVIZ_FRAGMENT'

# ── Exaviz Cruiser CM5 ────────────────────────────────────────────────────────
# Appended by qemu-archstrap-image-rpi5
# Ref: https://github.com/Lonewolf-Information-systems/CM5-Exaviz

arm_64bit=1

# PCIe x1 gen3 — M.2 slots (Axelera Metis AX2520 + NVMe)
dtparam=pciex1=on
dtparam=pciex1_gen=3

# NVMe on CM5 M.2
dtparam=nvme=on

# UART debug — keep until bring-up confirmed stable
enable_uart=1
uart_2ndstage=1

# SATA via PCIe bridge on Exaviz Cruiser
# dtoverlay=exaviz-sata        # uncomment once exaviz-dt-overlays available

# Minimal GPU memory — headless NVR/NAS
gpu_mem=16

# Fan header — adjust gpiopin to Exaviz Cruiser schematic
# dtoverlay=gpio-fan,gpiopin=14,temp=60000
# ─────────────────────────────────────────────────────────────────────────────
EXAVIZ_FRAGMENT

    ok "config.txt finalised:"
    grep -v '^#' "${esp}/config.txt" | grep -v '^$' | sed 's/^/    /'
}

# ── first-boot-growfs deployment ──────────────────────────────────────────────
deploy_first_boot_growfs() {
    local root="$1"
    info "Deploying first-boot-growfs..."

    install -Dm755 /dev/stdin \
        "${root}/usr/local/sbin/first-boot-growfs.sh" <<'GROWFS'
#!/usr/bin/env bash
# first-boot-growfs.sh — runs once, grows btrfs + recreates swap.img
set -euo pipefail
LOG="/var/log/first-boot-growfs.log"
exec > >(tee -a "$LOG") 2>&1
echo "── first-boot-growfs $(date) ──"

# Find root partition + base device
ROOT_DEV=$(findmnt -n -o SOURCE /)
if [[ "$ROOT_DEV" =~ (mmcblk[0-9]+|nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
    BASE_DEV="/dev/${BASH_REMATCH[1]}"; PART_NUM="${BASH_REMATCH[2]}"
elif [[ "$ROOT_DEV" =~ ^(/dev/)([a-z]+)([0-9]+)$ ]]; then
    BASE_DEV="/dev/${BASH_REMATCH[2]}"; PART_NUM="${BASH_REMATCH[3]}"
else
    echo "ERROR: Cannot parse root device: $ROOT_DEV"; exit 1
fi
echo "Device: $BASE_DEV  Partition: $PART_NUM"
echo "Media:  $(blockdev --getsize64 "$BASE_DEV" | numfmt --to=iec)"

# Grow partition to fill media
echo "Growing partition ${PART_NUM}..."
if command -v growpart &>/dev/null; then
    growpart "$BASE_DEV" "$PART_NUM" || true
else
    parted -s "$BASE_DEV" resizepart "$PART_NUM" 100%
fi
partprobe "$BASE_DEV" 2>/dev/null || true
udevadm settle

# Grow btrfs
echo "Growing btrfs..."
btrfs filesystem resize max /
btrfs filesystem usage / | head -6

# Recreate swap.img from placeholder
SWAP_PLACEHOLDER="/swap/swap.img.placeholder"
SWAP_IMG="/swap/swap.img"
SWAP_SIZE="${FIRST_BOOT_SWAP_SIZE:-4G}"

if [[ -f "$SWAP_PLACEHOLDER" ]]; then
    echo "Recreating swap.img (${SWAP_SIZE})..."
    mountpoint -q /swap || \
        mount -o subvol=@swap "$(findmnt -n -o SOURCE /)" /swap
    chattr +C /swap 2>/dev/null || true
    rm -f "$SWAP_PLACEHOLDER"
    fallocate -l "$SWAP_SIZE" "$SWAP_IMG" 2>/dev/null || \
        dd if=/dev/zero of="$SWAP_IMG" bs=1M \
           count=$(numfmt --from=iec "$SWAP_SIZE" | awk '{print int($1/1048576)}') \
           status=progress
    chmod 600 "$SWAP_IMG"
    mkswap  "$SWAP_IMG"
    swapon  "$SWAP_IMG"
    grep -q "swap.img" /etc/fstab || \
        echo "/swap/swap.img  none  swap  sw  0  0" >> /etc/fstab
    echo "swap active:"; swapon --show
else
    echo "No swap placeholder — skipping"
fi

echo "── Summary ──"
btrfs filesystem usage / | head -8
lsblk "$BASE_DEV"

# Disable self
rm -f /etc/first-boot-growfs.pending
systemctl disable first-boot-growfs.service
echo "── first-boot-growfs complete $(date) ──"
GROWFS

    # systemd unit
    install -Dm644 /dev/stdin \
        "${root}/usr/lib/systemd/system/first-boot-growfs.service" <<'UNIT'
[Unit]
Description=First boot: grow btrfs filesystem and recreate swap
ConditionPathExists=/etc/first-boot-growfs.pending
DefaultDependencies=no
After=local-fs-pre.target
Before=local-fs.target swap.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/first-boot-growfs.sh
RemainAfterExit=yes

[Install]
WantedBy=local-fs.target
UNIT

    touch "${root}/etc/first-boot-growfs.pending"
    arch-chroot "$root" systemctl enable first-boot-growfs.service
    ok "first-boot-growfs deployed"
}

# ── pack-image helper ─────────────────────────────────────────────────────────
# Called at end of build to strip swap.img + record packed size
pack_image() {
    local img="$1"
    info "Packing image: removing swap.img, shrinking btrfs..."

    local loop mtmp
    loop=$(losetup --find --partscan --show "$img")
    mtmp=$(mktemp -d)

    # mount @swap, remove swap.img, leave placeholder
    mount -o "${BTRFS_OPTS},subvol=@swap" "${loop}p2" "$mtmp"
    if [[ -f "${mtmp}/swap.img" ]]; then
        rm -f "${mtmp}/swap.img"
        touch "${mtmp}/swap.img.placeholder"
        ok "swap.img removed → placeholder left"
    fi
    sync; umount "$mtmp"

    # shrink btrfs
    mount -o "${BTRFS_OPTS}" "${loop}p2" "$mtmp"
    btrfs balance start -dusage=5 -musage=5 "$mtmp" 2>/dev/null || true
    btrfs filesystem resize minimum "$mtmp"
    local fs_bytes
    fs_bytes=$(btrfs filesystem show --raw "$mtmp" \
        | grep -oP 'size \K[0-9]+' | head -1)
    sync; umount "$mtmp"
    rmdir "$mtmp"

    # shrink partition + truncate image
    local esp_end=$(( 257 * 1024 * 1024 ))
    local headroom=$(( 32  * 1024 * 1024 ))
    local new_bytes=$(( esp_end + fs_bytes + headroom ))
    local new_mb=$(( new_bytes / 1024 / 1024 ))

    parted -s "$img" resizepart 2 "${new_mb}MiB"
    truncate -s "$new_bytes" "$img"
    losetup -d "$loop"

    ok "Packed image: $(du -h "$img" | cut -f1)  →  $img"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

# ── Create + partition ────────────────────────────────────────────────────────
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
mkfs.fat  -F32 -n "RPI5-EFI"  "$ESP_DEV"
mkfs.btrfs -L  "ARCH-ROOT" -f "$ROOT_DEV"

# ── Btrfs subvolumes ──────────────────────────────────────────────────────────
BTRFS_TMP=$(mktemp -d)
mount -o compress=zstd "$ROOT_DEV" "$BTRFS_TMP"
for sv in @ @boot @swap @snapshots @var_log @home @frigate @docker; do
    btrfs subvolume create "${BTRFS_TMP}/${sv}"
done
ok "Subvolumes created"
sync; umount "$BTRFS_TMP"; rmdir "$BTRFS_TMP"

# ── Mount ─────────────────────────────────────────────────────────────────────
mkdir -p "$MOUNT_ROOT"
mount -o "${BTRFS_OPTS},subvol=@"          "$ROOT_DEV" "$MOUNT_ROOT"
mkdir -p "${MOUNT_ROOT}"/{boot/efi,swap,.snapshots,var/log,home,media/frigate,var/lib/docker}
mount -o "${BTRFS_OPTS},subvol=@boot"      "$ROOT_DEV" "${MOUNT_ROOT}/boot"
mount -o "${BTRFS_OPTS},subvol=@swap"      "$ROOT_DEV" "${MOUNT_ROOT}/swap"
mount -o "${BTRFS_OPTS},subvol=@snapshots" "$ROOT_DEV" "${MOUNT_ROOT}/.snapshots"
mount -o "${BTRFS_OPTS},subvol=@var_log"   "$ROOT_DEV" "${MOUNT_ROOT}/var/log"
mount -o "${BTRFS_OPTS},subvol=@home"      "$ROOT_DEV" "${MOUNT_ROOT}/home"
mount -o "${BTRFS_OPTS},subvol=@frigate,nodatacow" \
                                            "$ROOT_DEV" "${MOUNT_ROOT}/media/frigate"
mount -o "${BTRFS_OPTS},subvol=@docker,nodatacow"  \
                                            "$ROOT_DEV" "${MOUNT_ROOT}/var/lib/docker"
mount "$ESP_DEV" "${MOUNT_ROOT}/boot/efi"
ok "All subvolumes mounted"

# ── swap.img — placeholder only (pack-image / first-boot recreates) ───────────
chattr +C "${MOUNT_ROOT}/swap" 2>/dev/null || \
    warn "chattr +C on /swap failed — set nodatacow in fstab"
touch "${MOUNT_ROOT}/swap/swap.img.placeholder"
ok "swap placeholder created — first-boot-growfs will allocate swap.img"

# ── Bootstrap ─────────────────────────────────────────────────────────────────
[[ ! -f /usr/bin/qemu-aarch64-static ]] && die "qemu-aarch64-static not found"
mkdir -p "${MOUNT_ROOT}/usr/bin"
cp /usr/bin/qemu-aarch64-static "${MOUNT_ROOT}/usr/bin/"

pacstrap -C /etc/qemu-archstrap/pacman-aarch64.conf -K "$MOUNT_ROOT" \
    base base-devel \
    linux-rpi linux-rpi-headers linux-firmware \
    btrfs-progs \
    grub efibootmgr \
    dracut \
    dropbear \
    networkmanager openssh sudo \
    podman podman-docker \
    cockpit cockpit-podman \
    rpi-eeprom snapper \
    parted \
    namcap devtools \
    vim curl wget git

# ── Fetch + validate Lonewolf PKGBUILDs ───────────────────────────────────────
fetch_lonewolf_pkgbuilds

# ── fstab ─────────────────────────────────────────────────────────────────────
cat > "${MOUNT_ROOT}/etc/fstab" <<EOF
# qemu-archstrap rpi5/cm5 — btrfs subvolumes
UUID=${ROOT_UUID}  /                btrfs  ${BTRFS_OPTS},subvol=@            0 0
UUID=${ROOT_UUID}  /boot            btrfs  ${BTRFS_OPTS},subvol=@boot        0 0
UUID=${ROOT_UUID}  /swap            btrfs  ${BTRFS_OPTS},subvol=@swap,nodatacow  0 0
UUID=${ROOT_UUID}  /.snapshots      btrfs  ${BTRFS_OPTS},subvol=@snapshots   0 0
UUID=${ROOT_UUID}  /var/log         btrfs  ${BTRFS_OPTS},subvol=@var_log     0 0
UUID=${ROOT_UUID}  /home            btrfs  ${BTRFS_OPTS},subvol=@home        0 0
UUID=${ROOT_UUID}  /media/frigate   btrfs  ${BTRFS_OPTS},subvol=@frigate,nodatacow  0 0
UUID=${ROOT_UUID}  /var/lib/docker  btrfs  ${BTRFS_OPTS},subvol=@docker,nodatacow   0 0
UUID=${ESP_UUID}   /boot/efi        vfat   umask=0077                        0 2

# swap — populated by first-boot-growfs.service
# /swap/swap.img  none  swap  sw  0  0
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

# ── dracut ────────────────────────────────────────────────────────────────────
mkdir -p "${MOUNT_ROOT}/etc/dracut.conf.d"
cat > "${MOUNT_ROOT}/etc/dracut.conf.d/rpi5.conf" <<'EOF'
hostonly="yes"
hostonly_cmdline="yes"
compress="zstd"
add_dracutmodules+=" btrfs dropbear network "
filesystems+=" btrfs "
dropbear_acl="/etc/dropbear/authorized_keys"
dropbear_rsa_key="/etc/dropbear/dropbear_rsa_host_key"
dropbear_ecdsa_key="/etc/dropbear/dropbear_ecdsa_host_key"
kernel_cmdline="ip=dhcp"
add_drivers+=" broadcom vc4 drm "
EOF

# ── dropbear keys ─────────────────────────────────────────────────────────────
mkdir -p "${MOUNT_ROOT}/etc/dropbear"
arch-chroot "$MOUNT_ROOT" \
    dropbearkey -t rsa   -f /etc/dropbear/dropbear_rsa_host_key -s 4096
arch-chroot "$MOUNT_ROOT" \
    dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key

if [[ -f "$DROPBEAR_AUTHKEYS" ]]; then
    install -Dm600 "$DROPBEAR_AUTHKEYS" \
        "${MOUNT_ROOT}/etc/dropbear/authorized_keys"
    ok "authorized_keys injected"
else
    warn "No authorized_keys at ${DROPBEAR_AUTHKEYS} — early SSH will not work"
    touch "${MOUNT_ROOT}/etc/dropbear/authorized_keys"
fi

# ── initramfs ─────────────────────────────────────────────────────────────────
KERNEL_VER=$(ls "${MOUNT_ROOT}/lib/modules/" | head -1)
info "Kernel: ${KERNEL_VER}"
arch-chroot "$MOUNT_ROOT" dracut --force --kver "$KERNEL_VER" \
    --add "btrfs dropbear network" \
    "/boot/initramfs-${KERNEL_VER}.img"
arch-chroot "$MOUNT_ROOT" dracut --force --no-hostonly --kver "$KERNEL_VER" \
    --add "btrfs dropbear network" \
    "/boot/initramfs-${KERNEL_VER}-fallback.img"
ok "initramfs built"

# ── UEFI firmware ─────────────────────────────────────────────────────────────
info "Downloading NumberOneGit rpi5-uefi ${RPI5_UEFI_VER}..."
UEFI_TMP=$(mktemp -d)
wget -q --show-progress "$RPI5_UEFI_URL" -O "${UEFI_TMP}/rpi5-uefi.zip" \
    || die "UEFI firmware download failed — check: $RPI5_UEFI_URL"
unzip -q "${UEFI_TMP}/rpi5-uefi.zip" -d "${UEFI_TMP}/uefi"

ESP="${MOUNT_ROOT}/boot/efi"
cp "${UEFI_TMP}/uefi/RPI_EFI.fd" "$ESP/"
cp "${UEFI_TMP}/uefi/"*.dat "$ESP/" 2>/dev/null || true
cp "${UEFI_TMP}/uefi/"*.elf "$ESP/" 2>/dev/null || true

# config.txt — zip base + Lonewolf fragment merge + Exaviz additions
deploy_config_txt "$ESP" "${UEFI_TMP}/uefi"

# ── GRUB ──────────────────────────────────────────────────────────────────────
arch-chroot "$MOUNT_ROOT" grub-install \
    --target=arm64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=ARCH \
    --removable \
    --recheck

KERNEL_IMG=$(ls "${MOUNT_ROOT}/boot/" | grep -E "^Image|^vmlinuz" | head -1)
INITRD_IMG="initramfs-${KERNEL_VER}.img"
INITRD_FBK="initramfs-${KERNEL_VER}-fallback.img"

cat > "${MOUNT_ROOT}/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5
set timeout_style=menu

menuentry "Arch Linux CM5 (btrfs @)" {
    linux   /boot/${KERNEL_IMG} \\
            root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=@ \\
            rw rd.luks=0 rd.md=0 rd.dm=0 \\
            ip=dhcp \\
            console=ttyAMA0,115200 console=tty1 quiet
    initrd  /boot/${INITRD_IMG}
}
menuentry "Arch Linux CM5 - Fallback" {
    linux   /boot/${KERNEL_IMG} \\
            root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=@ \\
            rw rd.luks=0 ip=dhcp \\
            console=ttyAMA0,115200 console=tty1
    initrd  /boot/${INITRD_FBK}
}
menuentry "UEFI Firmware Settings" { fwsetup }
EOF
ok "grub.cfg written"

# ── snapper ───────────────────────────────────────────────────────────────────
arch-chroot "$MOUNT_ROOT" snapper -c root create-config /
arch-chroot "$MOUNT_ROOT" systemctl enable \
    snapper-timeline.timer snapper-cleanup.timer

# ── Services ──────────────────────────────────────────────────────────────────
arch-chroot "$MOUNT_ROOT" systemctl enable \
    NetworkManager sshd cockpit.socket fstrim.timer

# ── first-boot-growfs ─────────────────────────────────────────────────────────
deploy_first_boot_growfs "$MOUNT_ROOT"

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -f "${MOUNT_ROOT}/usr/bin/qemu-aarch64-static"
warn "Root password not set — arch-chroot ${MOUNT_ROOT} passwd"

# ── Pack image ────────────────────────────────────────────────────────────────
# Unmount everything first (cleanup trap will also fire but we need it now
# to hand ROOT_DEV back to losetup for pack_image)
for mp in proc sys dev/pts dev run; do
    umount -l "${MOUNT_ROOT}/${mp}" 2>/dev/null || true
done
for mp in boot/efi boot swap .snapshots var/log home media/frigate var/lib/docker ""; do
    umount -l "${MOUNT_ROOT}/${mp}" 2>/dev/null || true
done
losetup -d "$LOOP_DEV"; LOOP_DEV=""

pack_image "$IMG"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}── CM5/RPi5 Image Ready ──────────────────────────────────────────${NC}"
echo -e "  Image       : ${CYAN}${IMG}${NC}"
echo -e "  UEFI        : ${CYAN}NumberOneGit rpi5-uefi ${RPI5_UEFI_VER}${NC}"
echo -e "  CM5 PKGBUILDs: ${CYAN}Lonewolf CM5-Exaviz → /usr/local/src/CM5-Exaviz${NC}"
echo -e "  Btrfs       : ${CYAN}@ @boot @swap @snapshots @var_log @home @frigate @docker${NC}"
echo -e "  Swap        : ${CYAN}first-boot-growfs recreates /swap/swap.img${NC}"
echo -e "  Boot chain  : ${CYAN}EEPROM → RPI_EFI.fd → grubaa64.efi → linux-rpi${NC}"
echo -e "  Initramfs   : ${CYAN}dracut + btrfs + dropbear${NC}"
echo -e "  Early SSH   : ${CYAN}ssh -p 222 root@<ip>${NC}"
echo ""
echo -e "  Flash:"
echo -e "    ${YELLOW}dd if=${IMG} of=/dev/sdX bs=4M status=progress conv=fsync${NC}"
echo -e "    ${YELLOW}bmaptool copy ${IMG} /dev/sdX${NC}"
echo ""
echo -e "  Validate CM5 PKGBUILDs on device:"
echo -e "    ${YELLOW}cd /usr/local/src/CM5-Exaviz/Arch-Linux/rpi5-uefi-cm5${NC}"
echo -e "    ${YELLOW}namcap PKGBUILD && makepkg -si${NC}"
echo -e "${GREEN}──────────────────────────────────────────────────────────────────${NC}"
