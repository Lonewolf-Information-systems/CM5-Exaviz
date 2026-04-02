# sys-kernel/axelera-metis-driver/axelera-metis-driver-9999.ebuild
# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit linux-mod-r1 udev

if [[ ${PV} == "9999" ]]; then
    inherit git-r3
    EGIT_REPO_URI="https://github.com/axelera-ai-hub/axelera-driver.git"
    EGIT_BRANCH="main"
    KEYWORDS=""
else
    SRC_URI="https://github.com/axelera-ai-hub/axelera-driver/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
    KEYWORDS="~amd64 ~arm64"
fi

DESCRIPTION="Axelera Metis AI accelerator PCIe kernel module"
HOMEPAGE="https://github.com/axelera-ai-hub/axelera-driver"

LICENSE="GPL-2"
SLOT="0"

# linux-mod-r1 pulls in virtual/linux-sources automatically via linux-info
# udev is runtime-only — not needed to build the module
RDEPEND="
    virtual/udev
"
BDEPEND=""

# MODULE_NAMES format: modname(install_subdir:source_dir)
# install_subdir = where under /lib/modules/<kv>/kernel/ it lands
# source_dir     = where the kbuild Makefile lives (${S} = repo root)
MODULE_NAMES="metis(kernel/axelera:${S})"

# Kernel config sanity checks — add any symbols the driver actually requires
# Check the driver source for: depends on FOO / select BAR
CONFIG_CHECK="
    ~PCI
    ~MODULES
    ~MODULE_UNLOAD
"

src_compile() {
    # linux-mod-r1_src_compile calls make with the correct KDIR/M= args
    # No need for BUILD_TARGETS — the eclass handles 'modules' target
    linux-mod-r1_src_compile
}

src_install() {
    linux-mod-r1_src_install

    # Install udev rule so /dev/metis* gets correct permissions
    # without requiring users to be root
    udev_dorules "${FILESDIR}/99-axelera-metis.rules"
}

pkg_postinst() {
    # Prints the "don't forget to depmod" and module load reminders
    linux-mod-r1_pkg_postinst
    udev_reload
}
