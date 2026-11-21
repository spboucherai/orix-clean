#!/usr/bin/env bash
# ORIX Clean — Scripts/check.sh
# Description: Repository hygiene: author header on first-party sources, no signing material, no credentials, no network code.
# Author: Simon-Pierre Boucher — contact@spboucher.ai
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
