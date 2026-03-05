#!/bin/bash
# dracut hook: pre-udev (runs before udev triggers)

# 1. Ensure ConfigFS is ready
if [ ! -d /sys/kernel/config/device-tree ]; then
    mount -t configfs none /sys/kernel/config 2>/dev/null
fi

# 2. Slam the Overlays
# This defines the hardware at the device-tree level
for overlay in exaviz-cruiser axelera-metis; do
    if [ -f "/lib/firmware/overlays/${overlay}.dtbo" ]; then
        mkdir -p "/sys/kernel/config/device-tree/overlays/${overlay}"
        cat "/lib/firmware/overlays/${overlay}.dtbo" > "/sys/kernel/config/device-tree/overlays/${overlay}/dtbo"
        echo "Exaviz-HAL: Slammed ${overlay} into ConfigFS"
    fi
done

# 3. Force PCIe Gen3 (The 'AMD64-ish' way)
# Targeting the RPi5/CM5 PCIe controller
if [ -d "/sys/devices/platform/axi/1000110000.pcie" ]; then
    echo 3 > /sys/devices/platform/axi/1000110000.pcie/pcie_gen_cap 2>/dev/null
    echo "Exaviz-HAL: Forced PCIe Gen3 Link Cap"
fi
