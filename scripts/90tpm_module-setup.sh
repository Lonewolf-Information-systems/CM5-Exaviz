#dracut/90tpm/module-setup.sh
install() {
    # Include TPM 2.0 stack and the SLB9670/9672 driver
    inst_multiple tpm2_pcrread tpm2_seal tpm2_unseal
    hostonly='' instmods tpm_tis_spi spi_bcm2835
    
    # The 'Slammer': Load the overlay before the kernel tries to find /dev/tpm0
    inst_script "$moddir/load-tpm-overlay.sh" "/sbin/tpm-init"
}
