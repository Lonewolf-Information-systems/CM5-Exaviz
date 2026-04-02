EAPI=8

# No cmake, no distutils — this is a binary blob + Python venv SDK
# distributed via git branches, not tarballs or pypi

inherit git-r3

if [[ ${PV} == "9999" ]]; then
    EGIT_REPO_URI="https://github.com/axelera-ai-hub/voyager-sdk.git"
    EGIT_BRANCH="latest"    # 'latest' branch = current release default
    KEYWORDS=""
else
    # Release branches are named release/vX.Y e.g. release/v1.5
    EGIT_REPO_URI="https://github.com/axelera-ai-hub/voyager-sdk.git"
    EGIT_BRANCH="release/v${PV}"
    KEYWORDS="~amd64 ~arm64"
fi

DESCRIPTION="Axelera Voyager SDK – runtime libraries and Python toolchain"
HOMEPAGE="https://github.com/axelera-ai-hub/voyager-sdk"

LICENSE="axelera-proprietary"   # check LICENSE file in repo; not MIT/Apache
SLOT="0"
IUSE="examples development"

# Runtime: pre-built .so blobs need glibc, libstdc++, udev
# Development: adds Python 3.10-3.12 + heavy ML stack
RDEPEND="
    sys-libs/glibc
    sys-libs/libstdc++
    virtual/libudev
    sys-kernel/axelera-metis-driver
    development? (
        dev-python/numpy
        dev-python/pyyaml
        dev-python/requests
        dev-python/tqdm
        dev-python/python-dateutil
        dev-python/typing-extensions
        dev-python/onnx
        dev-python/torch
        dev-python/opencv-python
    )
    examples? (
        dev-python/pillow
        dev-python/opencv-python
    )
"
BDEPEND="
    app-arch/tar
    dev-vcs/git
"

# SDK installs to /opt/axelera — use INSTALL_PREFIX
AX_PREFIX="/opt/axelera"

src_prepare() {
    default
    # Neutralise the installer's apt/pip/pyenv machinery
    # We manage deps via portage — strip pip/virtualenv/pyenv invocations
    sed -i \
        -e '/pip install/d'          \
        -e '/pyenv install/d'        \
        -e '/apt-get/d'              \
        -e '/virtualenv/d'           \
        -e '/--user/d'               \
        "${S}/install.sh" || die "sed on install.sh failed"
}

src_install() {
    # Runtime libraries land in /opt/axelera/<version>/
    # The installer uses AXELERA_VERSION from cfg yaml — replicate manually

    local axver="${PV}"
    [[ "${PV}" == "9999" ]] && axver="dev"

    into "${AX_PREFIX}/${axver}"

    # Install pre-built runtime libs
    if [[ -d "${S}/lib" ]]; then
        dolib.so "${S}"/lib/*.so* 2>/dev/null || true
    fi

    # Install headers for AxRuntime C/C++ API
    if [[ -d "${S}/include" ]]; then
        insinto "${AX_PREFIX}/${axver}/include"
        doins -r "${S}"/include/.
    fi

    # Install Python axelera package (non-pip, direct)
    if [[ -d "${S}/axelera" ]]; then
        insinto "$(python_get_sitedir)"
        doins -r "${S}"/axelera
    fi

    # CLI tools: axrunmodel, axdevice, axmonitor etc.
    if [[ -d "${S}/tools" ]]; then
        exeinto "${AX_PREFIX}/${axver}/bin"
        doexe "${S}"/tools/*
    fi

    # Model zoo YAML (examples USE flag)
    if use examples && [[ -d "${S}/ax_models" ]]; then
        insinto "${AX_PREFIX}/${axver}/models"
        doins -r "${S}"/ax_models/.
    fi

    # env.d so users get /opt/axelera/bin in PATH
    local envd="${T}/60axelera"
    cat > "${envd}" <<-EOF
        PATH="${AX_PREFIX}/${axver}/bin"
        LDPATH="${AX_PREFIX}/${axver}/lib"
        AXELERA_FRAMEWORK="${AX_PREFIX}/${axver}"
    EOF
    doenvd "${envd}"
}

pkg_postinst() {
    elog "Axelera Voyager SDK installed to ${AX_PREFIX}/${PV}"
    elog "Run: source /etc/profile.d/env.d  (or re-login) to activate PATH"
    elog ""
    elog "For the Python development environment, activate with:"
    elog "  source ${AX_PREFIX}/${PV}/venv/bin/activate"
    elog ""
    elog "Kernel driver must be loaded: modprobe metis"
}
