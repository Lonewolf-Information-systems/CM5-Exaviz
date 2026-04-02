#!/bin/bash
# dracut module: 99dt-overlay
# Applies .dtbo overlays at boot via configfs
# Runs after udev settles, before pivot_root

check() {
    # Always include on aarch64 with DTB present
    [[ -f /boot/firmware/bcm2712-rpi-cm5.dtb ]] || return 1
    return 0
}

depends() {
    echo "kernel-modules"
}

installkernel() {
    # Pull in overlay engine and configfs
    instmods configfs of_overlay
    # GPIO/pinctrl needed for BT and Exaviz switch GPIOs
    instmods gpio_raspberrypi pinctrl-rp1
    # Bluetooth stack (BT is GPIO/UART sourced on CM5)
    instmods hci_uart btbcm bluetooth rfkill
    # PCIe for Metis + NVMe
    instmods pcie-brcmstb nvme nvme-core
    # RTL8365MB DSA switch driver (Exaviz Cruiser)
    instmods rtl8365mb realtek_smi
    # USB 3.0 for RTL8156BG WAN (2.5GbE)
    instmods r8152
}

install() {
    inst_script "$moddir/apply-overlays.sh" /sbin/apply-dt-overlays.sh

    # Hook into initqueue/settled — runs after udev, before rootfs mount
    # rd.driver.post equivalent but for DTB, not just modules
    inst_hook initqueue/settled 50 "$moddir/apply-overlays.sh"

    # DTB overlays to embed
    for dtbo in \
        /boot/firmware/overlays/cruiser-raspberrypi-cm5.dtbo \
        /boot/firmware/overlays/disable-bt.dtbo; do
        [[ -f "${dtbo}" ]] && inst_simple "${dtbo}"
    done

    # Base DTB
    inst_simple /boot/firmware/bcm2712-rpi-cm5.dtb
}
