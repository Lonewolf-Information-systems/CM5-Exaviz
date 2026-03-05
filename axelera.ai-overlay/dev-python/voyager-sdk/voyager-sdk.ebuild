EAPI=8

PYTHON_COMPAT=( python3_{10..12} )

inherit distutils-r1

DESCRIPTION="Axelera Voyager SDK – Python runtime components"
HOMEPAGE="https://github.com/axelera-ai-hub/voyager-sdk"
SRC_URI="https://github.com/axelera-ai-hub/voyager-sdk/archive/refs/tags/v${PV}.tar.gz -> voyager-sdk-${PV}.tar.gz"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

IUSE="examples"

RDEPEND="
	dev-python/numpy[${PYTHON_USEDEP}]
	dev-python/pyyaml[${PYTHON_USEDEP}]
	dev-python/requests[${PYTHON_USEDEP}]
	dev-python/tqdm[${PYTHON_USEDEP}]
	dev-python/python-dateutil[${PYTHON_USEDEP}]
	dev-python/typing-extensions[${PYTHON_USEDEP}]
	examples? (
		dev-python/opencv-python[${PYTHON_USEDEP}]
		dev-python/pillow[${PYTHON_USEDEP}]
	)
"

DEPEND="${RDEPEND}"

S="${WORKDIR}/voyager-sdk-${PV}"

src_prepare() {
	default

	# Prevent vendored wheels / downloads
	sed -i \
		-e '/pip install/d' \
		-e '/--user/d' \
		-e '/virtualenv/d' \
		. || die
}

src_install() {
	distutils-r1_src_install

	# Install CLI entrypoints if not auto-installed
	if [[ -d tools ]]; then
		exeinto /usr/bin
		doexe tools/*.py
	fi
}
