PODMAN_PACKAGES=(
    podman
    podman-docker          # docker CLI shim → podman
    cockpit
    cockpit-podman
    cockpit-networkmanager
    cockpit-storaged       # btrfs/SATA disk management in UI
    cockpit-packagekit     # package updates via UI
    buildah                # image builds if needed
    crun                   # OCI runtime (faster than runc on aarch64)
)
