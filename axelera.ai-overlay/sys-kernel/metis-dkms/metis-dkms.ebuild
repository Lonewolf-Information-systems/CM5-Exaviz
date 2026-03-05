EAPI=8

DESCRIPTION="Axelera Metis PCIe DKMS kernel module"
HOMEPAGE="https://github.com/axelera-ai-hub/axelera-driver"
SRC_URI="https://github.com/axelera-ai-hub/axelera-driver/archive/refs/tags/v${PV}.tar.gz -> metis-${PV}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE=""

DEPEND="sys-kernel/dkms"
RDEPEND="
	sys-kernel/dkms
	virtual/kernel
"

S="${WORKDIR}/axelera-driver-${PV}"

src_install() {
	insinto /usr/src/metis-${PV}
	doins -r .

	# Install dkms.conf
	insinto /usr/src/metis-${PV}
	doins "${FILESDIR}/dkms.conf"
}
