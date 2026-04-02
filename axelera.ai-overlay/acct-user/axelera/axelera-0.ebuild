# acct-user/axelera/axelera-0.ebuild  
# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-user

DESCRIPTION="User for Axelera Metis AIPU daemon/service"

ACCT_USER_ID=           # dynamic UID
ACCT_USER_SHELL="/sbin/nologin"
ACCT_USER_HOME="/var/lib/axelera"
ACCT_USER_HOME_OWNER="axelera:axelera"
ACCT_USER_GROUPS=( axelera )

KEYWORDS="~amd64 ~arm64"
