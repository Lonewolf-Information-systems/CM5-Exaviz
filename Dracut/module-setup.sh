#!/bin/bash
# /usr/lib/dracut/modules.d/95rpi-hardware/module-setup.sh

check() {
    # Only include this if we are on an ARM64 RPi
    [[ "$(uname -m)" == "aarch64" ]] || return 1
    return 0
}

depends() {
    echo "bash"
}

install() {
    # Include the Axelera driver and RPi5 I/O drivers
    inst_mods axdevice rp1_uart rp1_pci
    
    # Include the specific DTBOs in the initramfs
    inst "/boot/overlays/exaviz-cruiser.dtbo" "/boot/overlays/exaviz-cruiser.dtbo"
    inst "/boot/overlays/axelera-metis.dtbo" "/boot/overlays/axelera-metis.dtbo"
}
