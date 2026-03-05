EAPI=8

inherit cmake

DESCRIPTION="Native SDK & libraries for Voyager"
HOMEPAGE="https://github.com/axelera-ai-hub/voyager-sdk"
SRC_URI="..."

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

DEPEND=">=dev-lang/cpp11 ..."
RDEPEND=""

src_install() {
    cmake_configure -DCMAKE_BUILD_TYPE=Release
    cmake_install
}
