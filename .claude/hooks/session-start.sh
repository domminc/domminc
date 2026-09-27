#!/bin/bash
# Cloud sessions only: make Playwright / Chrome DevTools MCP able to open pages.
# 1) use the bundled Chromium (no Google Chrome in the container)
# 2) trust the container's TLS proxy CA in Chromium's NSS store
[ "$CLAUDE_CODE_REMOTE" = "true" ] || exit 0
cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0

CHROME=$(readlink -f /opt/pw-browsers/chromium 2>/dev/null)
[ -x "$CHROME" ] || exit 0

if ! command -v certutil >/dev/null 2>&1; then
  apt-get install -y -q libnss3-tools >/dev/null 2>&1 \
    || { apt-get update -q >/dev/null 2>&1 && apt-get install -y -q libnss3-tools >/dev/null 2>&1; }
fi
BUNDLE=/root/.ccr/ca-bundle.crt
NSSDB="sql:$HOME/.pki/nssdb"
if command -v certutil >/dev/null 2>&1 && [ -f "$BUNDLE" ]; then
  mkdir -p "$HOME/.pki/nssdb"
  [ -f "$HOME/.pki/nssdb/cert9.db" ] || certutil -N -d "$NSSDB" --empty-password
  TMP=$(mktemp -d)
  awk -v d="$TMP" '/BEGIN CERT/{n++} n{print > (d "/" n ".pem")}' "$BUNDLE"
  for f in "$TMP"/*.pem; do
    if openssl x509 -in "$f" -noout -subject 2>/dev/null | grep -q "CCR Upstream Proxy CA"; then
      certutil -A -d "$NSSDB" -n "ccr-proxy-ca-$(basename "$f" .pem)" -t "C,," -i "$f" 2>/dev/null
    fi
  done
  rm -rf "$TMP"
fi

# Local-scope overrides of the .mcp.json entries (this container only)
if ! claude mcp get playwright 2>/dev/null | grep -q -- "--executable-path"; then
  claude mcp remove playwright -s local >/dev/null 2>&1
  claude mcp add -s local playwright -- npx @playwright/mcp@latest \
    --executable-path "$CHROME" --headless --no-sandbox --isolated >/dev/null 2>&1
fi
if ! claude mcp get chrome-devtools 2>/dev/null | grep -q -- "--executablePath"; then
  claude mcp remove chrome-devtools -s local >/dev/null 2>&1
  claude mcp add -s local chrome-devtools -- npx chrome-devtools-mcp@latest \
    --executablePath "$CHROME" --headless --isolated \
    --chrome-arg=--no-sandbox --chrome-arg=--disable-setuid-sandbox >/dev/null 2>&1
fi
exit 0
