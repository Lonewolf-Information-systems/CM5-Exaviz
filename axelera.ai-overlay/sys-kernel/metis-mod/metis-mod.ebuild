EAPI=8

inherit linux-mod-r1

DESCRIPTION="Axelera Metis AI accelerator kernel module"
HOMEPAGE="https://github.com/axelera-ai-hub/axelera-driver"
SRC_URI="https://github.com/axelera-ai-hub/axelera-driver/archive/refs/tags/v1.5.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

DEPEND="virtual/linux-sources"
RDEPEND=""

MODULE_NAMES="metis(driver:${S})"
BUILD_TARGETS="modules"
