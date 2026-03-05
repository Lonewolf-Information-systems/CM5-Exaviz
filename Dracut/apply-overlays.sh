#!/bin/sh
# Portable script to apply overlays via ConfigFS in the initramfs
type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

# Mount ConfigFS if it's not already there
if [ ! -d /sys/kernel/config/device-tree ]; then
    mount -t configfs none /sys/kernel/config
fi

# Apply each overlay found in our firmware directory
for dtbo in /lib/firmware/overlays/*.dtbo; do
    name=$(basename "$dtbo" .dtbo)
    mkdir -p "/sys/kernel/config/device-tree/overlays/$name"
    cat "$dtbo" > "/sys/kernel/config/device-tree/overlays/$name/dtbo"
    info "Cruiser-HAL: Loaded $name"
done
