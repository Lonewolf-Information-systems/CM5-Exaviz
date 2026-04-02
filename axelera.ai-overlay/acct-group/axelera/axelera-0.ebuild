# acct-group/axelera/axelera-0.ebuild
# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-group

DESCRIPTION="Group for Axelera Metis AIPU device access"
ACCT_GROUP_ID=   # leave unset — dynamic GID assigned by system

KEYWORDS="~amd64 ~arm64"
