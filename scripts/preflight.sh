#!/bin/sh
# Exaviz/Axelera Hardware Pre-Flight

echo "--- 🧠 Memory & CMA Check ---"
grep -E "Cma|MemTotal" /proc/meminfo

echo "--- 🚀 PCIe Link Check (Axelera) ---"
# Check if the AI chip is running at Gen3
lspci -vvv -d 1e81: | grep -E "LnkCap|LnkSta"

echo "--- 🔗 Udev Symlink Check ---"
for dev in /dev/gps0 /dev/axelera0 /dev/cruiser-iot; do
    [ -L "$dev" ] && echo "✅ $dev -> $(readlink -f $dev)" || echo "❌ $dev MISSING"
done
