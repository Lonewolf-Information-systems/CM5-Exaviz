# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit linux-mod-r1

if [[ ${PV} == "9999" ]]; then
    inherit git-r3
    EGIT_REPO_URI="https://github.com/axelera-ai-hub/axelera-driver.git"
    EGIT_BRANCH="main"
    KEYWORDS=""
else
    SRC_URI="https://github.com/axelera-ai-hub/axelera-driver/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
    KEYWORDS="~amd64 ~arm64"
fi

DESCRIPTION="Out-of-tree kernel driver for the Axelera Metis M.2 AIPU"
HOMEPAGE="https://github.com/axelera-ai-hub/axelera-driver"

LICENSE="GPL-2"     # kernel modules must be GPL-2 compatible
SLOT="0"

# linux-mod-r1 handles DEPEND on virtual/linux-sources
# and kernel config checks automatically
DEPEND="
    acct-group/axelera
    acct-user/axelera
"
RDEPEND="
    ${DEPEND}
    virtual/udev
"
BDEPEND=""

# Declare the module to build
MODULE_NAMES="metis(kernel/axelera:${S})"

# Optional: enforce minimum kernel version (Metis likely needs 5.15+)
CONFIG_CHECK="~MODULES"

src_compile() {
    local modlist=( metis )
    local modargs=(
        KDIR="${KV_OUT_DIR}"
    )
    linux-mod-r1_src_compile
}

src_install() {
    linux-mod-r1_src_install

    # udev rule so /dev/metis* is accessible without root
    local udev_rules="${FILESDIR}/99-axelera-metis.rules"
    if [[ -f ${udev_rules} ]] ; then
        udev_dorules "${udev_rules}"
    fi
}

pkg_postinst() {
    linux-mod-r1_pkg_postinst   # prints depmod reminder
    udev_reload
}
