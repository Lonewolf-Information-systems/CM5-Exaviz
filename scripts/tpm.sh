# Force load SPI and TPM modules if not auto-detected
modprobe spi_bcm2835 2>/dev/null
modprobe tpm_tis_spi 2>/dev/null

# Wait for /dev/tpm0 to appear (timeout 5s)
timeout 5 sh -c 'until [ -e /dev/tpm0 ]; do sleep 0.5; done'
