# /etc/axelera/metis-setup.sh
# Post-boot Metis M.2 bring-up on CM5

# Verify PCIe enumeration
lspci | grep -i axelera   # should show AX2520

# Axelera runtime install (aarch64)
# https://github.com/axelera-ai/axelera-runtime
# Currently requires their SDK — register at axelera.ai/developers

# udev rule for Metis device node
cat > /etc/udev/rules.d/99-axelera-metis.rules <<'EOF'
SUBSYSTEM=="pci", ATTR{vendor}=="0x1f0f", ATTR{device}=="0x0001", \
    GROUP="axelera", MODE="0660", TAG+="systemd"
EOF

groupadd -r axelera 2>/dev/null || true
usermod -aG axelera frigate
usermod -aG axelera hass
