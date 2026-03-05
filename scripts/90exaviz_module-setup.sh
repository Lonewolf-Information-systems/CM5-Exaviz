#dracut/90exaviz/module-setup.sh
install() {
    # Reusing your 'slammer' for TPM, AI, and PoE
    inst_multiple sh mkdir cat find
    inst_script "$moddir/exaviz-init.sh" "/sbin/exaviz-init"
    
    # Ensure we have the I2C/SPI drivers if using an external TPM
    hostonly='' instmods i2c-dev tpm_tis_spi tpm_tis_i2c
}
