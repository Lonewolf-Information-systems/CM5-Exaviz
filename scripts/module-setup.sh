#!/bin/bash
check() { return 0; } # Always include
depends() { echo "bash"; }

install() {
    # 1. Install binaries needed for the slammer
    inst_multiple mkdir cat mount modprobe

    # 2. Install the actual boot-time hook
    # Place it in 'pre-udev' so hardware is defined before udev scans
    inst_hook pre-udev 90 "$moddir/exaviz-slammer.sh"

    # 3. Include your DTBO blobs
    inst_dir /lib/firmware/overlays
    inst_multiple /lib/firmware/overlays/exaviz-cruiser.dtbo
    inst_multiple /lib/firmware/overlays/axelera-metis.dtbo
}

installkernel() {
    # Ensure ConfigFS and Device Tree Overlay support are loaded
    hostonly='' instmods configfs
}
