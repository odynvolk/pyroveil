#!/bin/bash
# Cross-build the layer for x86_64 on an ARM64 host (Steam snap + FEX setups).
#
# Installs into $PREFIX (default: ~/pyroveil-x86_64) as
#   $PREFIX/lib/libVkLayer_pyroveil_64.so
#   $PREFIX/share/vulkan/implicit_layer.d/VkLayer_pyroveil_64.json
# so install-steam-snap-layer.sh can pick it up.
set -e
cd "$(dirname "$0")/.."

PREFIX="${1:-$HOME/pyroveil-x86_64}"
BUILD=build-x86_64

# The project declares LANGUAGES CXX C, so both drivers are needed even though
# only the C++ one links the layer.
missing=()
for cc in x86_64-linux-gnu-gcc x86_64-linux-gnu-g++; do
	command -v "$cc" >/dev/null || missing+=("$cc")
done
if [ ${#missing[@]} -gt 0 ]; then
	echo "Missing cross compiler(s): ${missing[*]}" >&2
	echo "On Ubuntu/Debian:" >&2
	echo "  sudo apt-get install g++-x86-64-linux-gnu gcc-x86-64-linux-gnu" >&2
	echo "Those pull the matching target libc/libstdc++ headers and binutils" >&2
	echo "automatically, so there is no need to name a GCC version." >&2
	exit 1
fi

# The toolchain seeds the compiler as a cache entry, so a build directory that
# already exists keeps whatever compiler it was first configured with. Catch that
# before spending minutes building the wrong ABI.
if [ -f "$BUILD/CMakeCache.txt" ]; then
	cached="$(sed -n 's/^CMAKE_CXX_COMPILER:[A-Za-z]*=//p' "$BUILD/CMakeCache.txt" | head -1)"
	case "$(basename "$cached" 2>/dev/null)" in
		x86_64-linux-gnu-g++|"") ;;
		*)
			echo "ERROR: $BUILD is configured to use '$cached', not the x86_64 cross compiler." >&2
			echo "       A pre-existing build directory keeps its original compiler, so" >&2
			echo "       delete $BUILD and run this script again." >&2
			exit 1 ;;
	esac
fi

cmake . -B"$BUILD" -G Ninja \
	-DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/x86_64-linux-gnu.cmake \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="$PREFIX"
ninja -C"$BUILD" install

SO="$PREFIX/lib/libVkLayer_pyroveil_64.so"
MANIFEST="$PREFIX/share/vulkan/implicit_layer.d/VkLayer_pyroveil_64.json"
[ -f "$SO" ] || { echo "ERROR: build produced no $SO" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "ERROR: build produced no $MANIFEST" >&2; exit 1; }

# Assert the ABI the FEX guest needs. Getting this wrong is silent otherwise:
# the install succeeds, the loader simply lists no layer, and the failure only
# resurfaces as a game that still crashes. A stale $BUILD cache configured
# before the toolchain file existed reproduces exactly that. cross readelf ships
# with the toolchain; fall back to file(1) and only skip if neither is present.
machine() {
	if command -v x86_64-linux-gnu-readelf >/dev/null; then
		x86_64-linux-gnu-readelf -h "$1" 2>/dev/null | sed -n 's/^ *Machine: *//p'
	elif command -v file >/dev/null; then
		file -b "$1" 2>/dev/null
	fi
}

abi="$(machine "$SO" || true)"
if [ -z "$abi" ]; then
	echo "WARNING: neither readelf nor file is available, ABI not verified" >&2
elif ! printf '%s' "$abi" | grep -qiE 'x86-64|x86_64'; then
	echo "ERROR: $SO is not x86-64 (got: $abi)." >&2
	echo "       The FEX guest uses an x86-64 Vulkan loader, so an aarch64 layer" >&2
	echo "       is never loaded. If $BUILD was configured without the toolchain" >&2
	echo "       file, delete the directory and rebuild." >&2
	exit 1
fi

echo
echo "Installed (ABI verified):"
echo "  library   $SO"
echo "            $abi"
echo "  manifest  $MANIFEST"
