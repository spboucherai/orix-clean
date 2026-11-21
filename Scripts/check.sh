#!/usr/bin/env bash
# =============================================================================
#                  SP BOUCHER | INFRASTRUCTURE & AUTOMATION
#             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
# =============================================================================
#
# Project          : ORIX Clean
# File             : Scripts/check.sh
# Description      : Repository hygiene: author header on first-party sources,
#                    no signing material, no credentials, no network code.
# Module           : Scripts
# Repository       : https://git.spboucher.ai/orix-clean
# Created          : 2026-11-21
# Last Modified    : 2026-11-21
#
# Author           : Simon-Pierre Boucher
# Position         : Professor of Finance
# Institution      : Université du Québec en Outaouais (UQO)
# Organization     : SP Boucher
# Website          : https://spboucher.ai
# Git              : https://git.spboucher.ai
#
# Preferred Contact: support@spboucher.ai
# Technical Contact: dev@spboucher.ai
# Security/Admin   : admin@spboucher.ai
#
# Copyright (c) 2026
# Simon-Pierre Boucher
# All rights reserved where applicable. This file is governed by the
# applicable project license, copyright notices and relevant law.
# Existing third-party rights and notices remain unaffected.
#
# License          : Proprietary, all rights reserved (see license file)
# License File     : LICENSE
#
# Do not embed credentials, private keys, access tokens,
# certificates or confidential personal information.
#
# =============================================================================
# END OF SP BOUCHER SOURCE HEADER
# =============================================================================

set -uo pipefail
cd "$(dirname "$0")/.."
status=0
echo "== headers"
while IFS= read -r f; do head -8 "$f" | grep -q "Author: Simon-Pierre Boucher" || { echo "missing header: $f"; status=1; }; done \
  < <(git ls-files -co --exclude-standard -- '*.swift' '*.sh' '*.py' 'project.yml')
echo "== signing material"
git ls-files -co --exclude-standard | grep -E '\.(p8|p12|cer|mobileprovision|provisionprofile|keychain|pem)$|(^|/)\.env|AuthKey_' && status=1
echo "== secrets"
patterns='-----BEGIN [A-Z ]*PRIVATE KEY-----|AuthKey_[A-Z0-9]{10}|(api[_-]?key|apikey|secret|token|password|passwd)["'"'"' ]*[:=] *["'"'"'][^"'"'"' ]{8,}|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,}|192\.168\.[0-9]+\.[0-9]+|100\.[0-9]+\.[0-9]+\.[0-9]+|10\.67\.[0-9]+\.[0-9]+'
hits=$(git ls-files -co --exclude-standard | grep -vE '\.(png|jpg|pdf|icns)$|^Scripts/check\.sh$' | tr '\n' '\0' | xargs -0 grep -nIE "$patterns" 2>/dev/null || true)
[[ -n "$hits" ]] && { echo "$hits" | cut -c1-200; status=1; }
echo "== no network code in the product"
net=$(grep -rnE "URLSession|NWConnection|CFSocket|import Network|URLRequest|WKWebView" App/Sources Packages/ORIXCleanCore/Sources/ORIXCleanCore || true)
[[ -n "$net" ]] && { echo "$net"; status=1; }
echo "== no private API / privilege escalation"
priv=$(grep -rnE "AuthorizationExecuteWithPrivileges|SMJobBless|NSAppleScript|/usr/bin/sudo|dlopen\(|_CS|csrutil" App/Sources Packages/ORIXCleanCore/Sources/ORIXCleanCore || true)
[[ -n "$priv" ]] && { echo "$priv"; status=1; }
[[ $status -eq 0 ]] && echo "clean" || echo "FINDINGS"
exit $status
