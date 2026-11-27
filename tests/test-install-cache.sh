#!/usr/bin/env bash
# Hermetic test for scripts/install-steam-snap-layer.sh: a hack that ships
# pre-patched SPIR-V in cache/ must have it installed, not just an empty dir.
#
# The installer is Linux/snap-only, so `file` and `realpath -m` are shimmed to
# keep this runnable on any host. Run: bash tests/test-install-cache.sh
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
FAILURES=0

# errexit applies inside EXIT traps; without || true a failed chmod leaks $WORK.
cleanup() { chmod -R u+rwX "$WORK" 2>/dev/null || true; rm -rf "$WORK" || true; }
trap cleanup EXIT

ok()   { echo "  ok   - $1"; }
fail() { echo "  FAIL - $1"; FAILURES=$((FAILURES + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

count() { ls -1A "$1" 2>/dev/null | wc -l | tr -d ' '; }

# --- prerequisites -----------------------------------------------------------
# The installer rewrites the manifest with python3, so it is a hard dependency.
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

# --- shims -------------------------------------------------------------------
# || true: command -v returns 1 when the tool is absent (slim CI images), which
# under set -e would abort here with no message.
REAL_FILE="$(command -v file || true)"
REAL_REALPATH="$(command -v realpath || true)"
mkdir -p "$WORK/bin"

cat >"$WORK/bin/file" <<SHIM
#!/bin/bash
if [ -n "\${FAKE_FILE_OUTPUT:-}" ]; then
	echo "\$1: \$FAKE_FILE_OUTPUT"
elif [ -n "$REAL_FILE" ]; then
	exec "$REAL_FILE" "\$@"
else
	echo "\$1: data"
fi
SHIM

cat >"$WORK/bin/realpath" <<SHIM
#!/bin/bash
# BSD realpath has no -m; emulate "canonicalize, path may not exist".
if [ "\$1" = "-m" ]; then
	shift
	python3 - "\$@" <<'PY'
import os, sys
for p in sys.argv[1:]:
	print(os.path.realpath(p))
PY
elif [ -n "$REAL_REALPATH" ]; then
	exec "$REAL_REALPATH" "\$@"
else
	exec python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "\$@"
fi
SHIM

chmod +x "$WORK/bin/file" "$WORK/bin/realpath"
export PATH="$WORK/bin:$PATH"

# --- fake environment --------------------------------------------------------
SUC="$WORK/snap/steam/common"
PREFIX="$WORK/pyroveil-x86_64"
mkdir -p "$SUC/x86_rootfs/usr/share/vulkan/implicit_layer.d" \
         "$PREFIX/lib" "$PREFIX/share/vulkan/implicit_layer.d"

# Text stand-in: the ABI guard is a grep on `file` output, which the shim drives.
printf 'fake x86_64 layer\n' >"$PREFIX/lib/libVkLayer_pyroveil_64.so"
cat >"$PREFIX/share/vulkan/implicit_layer.d/VkLayer_pyroveil_64.json" <<'JSON'
{ "file_format_version": "1.1.2",
  "layer": { "name": "VK_LAYER_pyroveil", "type": "GLOBAL",
             "library_path": "./libVkLayer_pyroveil_64.so" } }
JSON

export SUC SRC_LIB="$PREFIX/lib/libVkLayer_pyroveil_64.so" \
       SRC_JSON="$PREFIX/share/vulkan/implicit_layer.d/VkLayer_pyroveil_64.json"
export FAKE_FILE_OUTPUT="ELF 64-bit LSB shared object, x86-64, version 1 (SYSV)"

# Captures output and exit status without letting set -e abort the suite.
install_layer() {
	install_rc=0
	install_out="$( cd "$REPO" && HACK="$1" bash scripts/install-steam-snap-layer.sh 2>&1 )" \
		|| install_rc=$?
}

MHW=hacks/monster-hunter-wilds-benchmark-nv/pyroveil.json
MHW_SRC="$REPO/hacks/monster-hunter-wilds-benchmark-nv"
MHW_DEST="$SUC/pyroveil/monster-hunter-wilds-benchmark-nv"
MHW_SPV_COUNT="$(find "$MHW_SRC/cache" -name '*.spv' | wc -l | tr -d ' ')"

# --- 1. a hack with a committed cache installs it ----------------------------
echo "test: hack shipping cache/*.spv"
install_layer "$MHW"
check "installer succeeded" '[ "$install_rc" -eq 0 ]'
check "reports the pre-patched shaders" 'echo "$install_out" | grep -q "pre-patched shader"'
check "every shipped .spv is installed ($MHW_SPV_COUNT expected)" \
	'[ "$(count "$MHW_DEST/cache")" = "$MHW_SPV_COUNT" ]'
check "installed bytes match the repo" '
	cmp -s "$MHW_DEST/cache/97ccc02f3db80d2e.spv" "$MHW_SRC/cache/97ccc02f3db80d2e.spv" &&
	cmp -s "$MHW_DEST/cache/97ccc02f3db80d2e.orig.spv" "$MHW_SRC/cache/97ccc02f3db80d2e.orig.spv"'
check "spirv-dis .asm dumps are not installed" '
	[ ! -e "$MHW_DEST/cache/97ccc02f3db80d2e.asm" ] &&
	[ ! -e "$MHW_DEST/cache/97ccc02f3db80d2e.old.asm" ]'
check "cache stays writable for the layer" '[ -w "$MHW_DEST/cache" ]'
check "config was installed" '[ -f "$MHW_DEST/pyroveil.json" ]'

# --- 2. re-running restores the committed patch ------------------------------
# Also proves copy_as's self-copy guard is not skipping the copy.
echo "test: reinstall restores a clobbered patch"
printf 'clobbered\n' >"$MHW_DEST/cache/97ccc02f3db80d2e.spv"
install_layer "$MHW"
check "reinstall succeeded" '[ "$install_rc" -eq 0 ]'
check "clobbered file is restored from the repo" \
	'cmp -s "$MHW_DEST/cache/97ccc02f3db80d2e.spv" "$MHW_SRC/cache/97ccc02f3db80d2e.spv"'
check "reinstall is idempotent" '[ "$(count "$MHW_DEST/cache")" = "$MHW_SPV_COUNT" ]'

# --- 3. a hack with no cache dir still gets a usable one ---------------------
echo "test: hack without a cache"
install_layer hacks/re-village-nvidia/pyroveil.json
REV_DEST="$SUC/pyroveil/re-village-nvidia"
check "installer succeeded" '[ "$install_rc" -eq 0 ]'
check "cache dir is created and writable" '[ -d "$REV_DEST/cache" ] && [ -w "$REV_DEST/cache" ]'
check "empty cache stays empty" '[ "$(count "$REV_DEST/cache")" = "0" ]'
check "no false warning" '! echo "$install_out" | grep -q "warning:"'

# --- 4. cache/ that holds no .spv must warn, not pass silently ---------------
echo "test: cache dir with only .asm dumps"
ASM="$WORK/hacks/asm-only"
mkdir -p "$ASM/cache"
printf '{"version":2,"type":"pyroveil","matches":[],"roundtripCache":"cache"}\n' >"$ASM/pyroveil.json"
printf 'disassembly\n' >"$ASM/cache/deadbeef.asm"
install_layer "$ASM/pyroveil.json"
check "installer still succeeded" '[ "$install_rc" -eq 0 ]'
check "warns that no .spv was found" 'echo "$install_out" | grep -q "has no .spv"'
check "cache dir left empty" '[ "$(count "$SUC/pyroveil/asm-only/cache")" = "0" ]'

# --- 5. hack outside the repo, path with a space -----------------------------
echo "test: hack path outside the repo containing a space"
SPACE="$WORK/my hacks/spaced game"
mkdir -p "$SPACE/cache"
printf '{"version":2,"type":"pyroveil","matches":[],"roundtripCache":"cache"}\n' >"$SPACE/pyroveil.json"
printf 'patched spirv\n' >"$SPACE/cache/1234abcd00000000.spv"
install_layer "$SPACE/pyroveil.json"
check "installer succeeded" '[ "$install_rc" -eq 0 ]'
check "spaced cache file installed verbatim" '
	cmp -s "$SUC/pyroveil/spaced game/cache/1234abcd00000000.spv" "$SPACE/cache/1234abcd00000000.spv"'

# --- 6. a bare filename must be rejected, not read the repo root -------------
echo "test: bare HACK filename is rejected"
install_layer "pyroveil.json"
check "rejected" '[ "$install_rc" -ne 0 ]'
check "explains the expected form" 'echo "$install_out" | grep -q "HACK must be a path"'
check "did not glob a cache out of the repo root" '[ ! -e "$SUC/pyroveil/cache" ]'

# --- 7. ABI guard still fires --------------------------------------------------
echo "test: ABI guard"
abi_rc=0
( export FAKE_FILE_OUTPUT="ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV)"
  cd "$REPO" && HACK="$MHW" bash scripts/install-steam-snap-layer.sh >/dev/null 2>&1 ) \
	|| abi_rc=$?
if [ "$abi_rc" -ne 0 ]; then
	ok "non-x86-64 library refused"
else
	fail "non-x86-64 library was accepted"
fi

abi_out="$( cd "$REPO" && FAKE_FILE_OUTPUT="ELF 64-bit LSB shared object, ARM aarch64" \
	HACK="$MHW" bash scripts/install-steam-snap-layer.sh 2>&1 )" || true
check "refusal names the ABI reason" 'echo "$abi_out" | grep -q "not x86-64"'

echo
if [ "$FAILURES" -eq 0 ]; then
	echo "all install-cache tests passed"
else
	echo "$FAILURES test(s) failed"
	exit 1
fi
