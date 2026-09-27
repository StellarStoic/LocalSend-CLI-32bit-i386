#!/bin/bash
# build.sh — cross-compile the LocalSend-protocol CLI for 32-bit x86 Linux (i686).
#
# LocalSend itself has no 32-bit Linux build and cannot have one: it is Flutter, and Flutter's
# Linux embedder only targets x64 / arm64 / riscv64. This uses a third-party MIT-licensed CLI
# implementation of the same protocol instead.
#
#   upstream CLI: https://github.com/tingkai-c/localsend-cli  (fork of meowrain/localsend-go)
#   protocol:     https://github.com/localsend/protocol
#
# Result: a static ELF 32-bit i386 binary, ~32 MB, no libc/libssl/GTK/Node dependencies at all —
# which is exactly what a 2010-era netbook needs.
set -euo pipefail

SRC="${SRC:-$PWD/localsend-cli}"
OUT="${OUT:-$PWD/localsend-cli-386}"
REF="${REF:-v1.3.2}"

command -v go >/dev/null || {
    echo "Go is required on the BUILD machine (1.22+). The target needs nothing." >&2
    echo "  e.g. curl -LO https://go.dev/dl/go1.24.7.linux-amd64.tar.gz && sudo tar -C /usr/local -xzf go1.24.7.linux-amd64.tar.gz" >&2
    exit 1
}

if [ ! -d "$SRC" ]; then
    git clone --depth 1 --branch "$REF" https://github.com/tingkai-c/localsend-cli.git "$SRC"
fi

cd "$SRC"

# Optional local patch: richer --help, a real --version, and flags-after-subcommand
# actually working. Skip it and you simply get upstream behaviour (the CLI still works).
PATCH=$(ls "$OLDPWD"/patches/*.patch 2>/dev/null | head -1 || true)
if [ -n "${PATCH:-}" ] && ! grep -q "main.version" main.go 2>/dev/null; then
    echo "applying $(basename "$PATCH")"
    git apply "$PATCH" || echo "  patch did not apply cleanly — building upstream code as-is"
fi

# CGO_ENABLED=0 -> fully static; no glibc version dependency on the target, no i686 libc needed
# -X main.version stamps the version string printed by --version
VER=$(git describe --tags --always 2>/dev/null || echo unknown)
CGO_ENABLED=0 GOOS=linux GOARCH=386 \
    go build -trimpath -ldflags="-s -w -X main.version=${VER}-local" -o "$OUT" .

echo "built: $OUT"
file "$OUT"
sha256sum "$OUT"
echo
echo "Copy it to the target and install system-wide:"
echo "  scp $OUT target:/tmp/ && ssh target 'sudo install -m0755 /tmp/$(basename "$OUT") /usr/local/bin/localsend-cli'"
echo
echo "Run on the target:"
echo "  localsend-cli                                  # TUI dashboard"
echo "  localsend-cli --quick-save receive             # headless receive"
echo "  localsend-cli send /path/to/file               # send (pick peer in the TUI)"
echo
echo "Go's linux/386 port is still first-class and requires SSE2, which every Atom N2xx has."
