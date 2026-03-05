#!/usr/bin/env bash
# exaviz-recon.sh
# Run on a Debian/Ubuntu system or in a debootstrap chroot
# to inspect what Exaviz actually packages before writing PKGBUILDs

EXAVIZ_REPO="${EXAVIZ_REPO:-https://apt.exaviz.com/debian}"  # placeholder — check their docs
EXAVIZ_DIST="${EXAVIZ_DIST:-bookworm}"

info() { echo -e "\033[0;36m[recon]\033[0m $*"; }

# ── Add their repo temporarily ────────────────────────────────────────────────
info "Adding Exaviz apt repo..."
curl -fsSL "${EXAVIZ_REPO}/gpg.key" | gpg --dearmor \
    > /tmp/exaviz-archive-keyring.gpg 2>/dev/null || \
    info "No GPG key found — repo URL may differ, check exaviz docs"

echo "deb [signed-by=/tmp/exaviz-archive-keyring.gpg] \
    ${EXAVIZ_REPO} ${EXAVIZ_DIST} main" \
    > /tmp/exaviz.list

apt-get update -o Dir::Etc::sourcelist=/tmp/exaviz.list \
               -o Dir::Etc::sourceparts=/dev/null \
               -o APT::Get::List-Cleanup=false 2>/dev/null || true

# ── List what they ship ───────────────────────────────────────────────────────
info "Packages matching exaviz/cruiser/cm5..."
apt-cache search --names-only \
    -o Dir::Etc::sourcelist=/tmp/exaviz.list \
    'exaviz\|cruiser\|cm5\|rpi5-carrier' 2>/dev/null || \
    info "apt-cache search failed — try manual inspection below"

# ── Download without installing — inspect contents ────────────────────────────
inspect_deb() {
    local pkg="$1"
    local outdir="/tmp/exaviz-inspect/${pkg}"
    mkdir -p "$outdir"
    info "Downloading ${pkg}..."
    apt-get download "$pkg" -o Dir::Cache="/tmp/exaviz-inspect" 2>/dev/null || {
        info "Could not download ${pkg} — may not exist"
        return 1
    }
    local debfile
    debfile=$(ls /tmp/exaviz-inspect/${pkg}*.deb 2>/dev/null | head -1)
    [[ -z "$debfile" ]] && return 1

    info "Contents of ${pkg}:"
    dpkg -c "$debfile"
    echo "---"
    info "Control/metadata:"
    dpkg -I "$debfile"
    echo "---"
    # extract for closer inspection
    dpkg -x  "$debfile" "${outdir}/root"
    dpkg -e  "$debfile" "${outdir}/DEBIAN"
    info "Extracted to ${outdir}"
}

# Likely package names to probe — adjust from their actual docs
for pkg in \
    exaviz-cruiser-firmware \
    exaviz-cruiser-dtb \
    exaviz-cruiser-kernel \
    exaviz-cm5-carrier \
    linux-image-exaviz \
    linux-dtb-exaviz \
    raspi-firmware-exaviz \
    exaviz-config \
    exaviz-tools; do
    inspect_deb "$pkg" 2>/dev/null || true
done

info "Check /tmp/exaviz-inspect/ for extracted contents"
info "Key things to find:"
info "  /boot/         — DTB overlays, firmware blobs"
info "  /lib/firmware/ — device firmware"
info "  /etc/          — config files, udev rules"
info "  /usr/lib/      — kernel modules"
