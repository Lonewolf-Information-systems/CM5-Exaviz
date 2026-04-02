EAPI=8

inherit linux-mod-r1

DESCRIPTION="Axelera Metis AI accelerator kernel module"
HOMEPAGE="https://github.com/axelera-ai-hub/axelera-driver"
SRC_URI="https://github.com/axelera-ai-hub/axelera-driver/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

DEPEND="virtual/linux-sources 
virtual/udev"

RDEPEND=""

MODULE_NAMES="metis(driver:${S})"
BUILD_TARGETS="modules"


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
