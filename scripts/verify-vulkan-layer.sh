#!/bin/bash
# Prove the layer is discoverable AND loadable by the x86_64 loader the FEX guest
# actually uses. Discovery alone is not enough: an ABI-mismatched layer can still
# be listed while failing to instantiate.
#
# Run after install-steam-snap-layer.sh and before blaming the game.
set -e
cd "$(dirname "$0")/.."

SUC="${SUC:-$HOME/snap/steam/common}"
NAME="${NAME:-re-village-nvidia}"
PROBE_DIR="$SUC/pyroveil"

command -v x86_64-linux-gnu-g++ >/dev/null || {
	echo "need the x86_64 cross compiler (see scripts/build-x86_64.sh)" >&2; exit 1; }
[ -d "$SUC/x86_rootfs" ] || { echo "no FEX rootfs at $SUC/x86_rootfs" >&2; exit 1; }

mkdir -p "$PROBE_DIR"
x86_64-linux-gnu-g++ -O1 -o "$PROBE_DIR/vk_layer_probe" tests/vk_layer_probe.cpp -ldl

# Written as a file and run inside the snap, so snapd supplies SNAP itself.
# Referencing \$SNAP from outside the snap resolves to nothing.
cat > "$PROBE_DIR/guest-probe.sh" <<EOFV2
#!/bin/bash
export FEX_ROOTFS="\$SNAP_USER_COMMON/x86_rootfs/"
export FEX_APP_CONFIG_LOCATION="\$SNAP_USER_COMMON/fex_config/"
export HOME="\$SNAP_USER_COMMON"
export PYROVEIL=1
export PYROVEIL_CONFIG="\$SNAP_USER_COMMON/pyroveil/$NAME/pyroveil.json"
"\$SNAP/usr/bin/bwrap" --bind / / --dev-bind /dev /dev --proc /proc \\
	--bind "\$SNAP_USER_COMMON" "\${FEX_ROOTFS%/}\$SNAP_USER_COMMON" -- \\
	"\$SNAP/usr/bin/FEXBash" -c "exec $PROBE_DIR/vk_layer_probe"
EOFV2
chmod +x "$PROBE_DIR/guest-probe.sh"

out="$(snap run --shell steam -c "bash $PROBE_DIR/guest-probe.sh" 2>&1)" || true

echo "$out" | grep -vE "VK_LAYER_(MESA|VALVE|MANGOHUD|RENDERDOC|INTEL|LUNARG)" || true
echo

if ! echo "$out" | grep -q "vkCreateInstance"; then
	echo "RESULT: probe did not run inside the guest."
	echo "Output was:"; echo "$out" | head -10
	exit 1
elif echo "$out" | grep -q "VK_SUCCESS"; then
	echo "RESULT: layer is discovered and loaded."
elif echo "$out" | grep -q "DISCOVERED VK_LAYER_pyroveil: NO"; then
	echo "RESULT: manifest not found in any directory the guest loader searches."
	echo "        Check $SUC/x86_rootfs/usr/share/vulkan/implicit_layer.d/"
	echo "        VK_ADD_LAYER_PATH will not help - pressure-vessel strips it."
	exit 1
else
	echo "RESULT: discovered but not loadable. Check the ABI:"
	file "$SUC/pyroveil/lib/libVkLayer_pyroveil_64.so" 2>/dev/null || true
	echo "        The FEX guest needs an x86-64 build (scripts/build-x86_64.sh)."
	exit 1
fi
