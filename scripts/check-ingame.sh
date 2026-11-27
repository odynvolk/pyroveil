#!/bin/bash
# Confirm the layer engaged during a real game session.
# The /proc/<pid>/maps check is the authoritative one; log and cache corroborate.
SUC="${SUC:-$HOME/snap/steam/common}"
APPID="${1:-1196590}"

CACHE="$(ls -d "$SUC"/pyroveil/*/cache 2>/dev/null | head -1)"

pid="$(pgrep -f "re8.exe|steam.exe" | tail -1)"
echo "=== loaded into the running game? ==="
if [ -n "$pid" ]; then
	if grep -q pyroveil "/proc/$pid/maps" 2>/dev/null; then
		echo "LOADED (pid $pid)"
		grep -o "/[^ ]*libVkLayer_pyroveil_64.so" "/proc/$pid/maps" | sort -u
	else
		echo "NOT LOADED (pid $pid) - run scripts/verify-vulkan-layer.sh"
	fi
else
	echo "no game process running"
fi

echo
echo "=== proton log ==="
log="$(find "$SUC" -name "steam-$APPID.log" -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d" " -f2-)"
if [ -n "$log" ]; then
	echo "path: $log"
	echo "pyroveil lines: $(grep -c pyroveil "$log")"
	grep pyroveil "$log" | grep -E "Found config|Found match|Pulled|Successfully placed" | head -6
else
	echo "none - PROTON_LOG_DIR must be inside SNAP_USER_COMMON"
fi

echo
echo "=== roundtrip cache ==="
if [ -n "$CACHE" ] && [ -d "$CACHE" ]; then
	echo "dir:   $CACHE"
	echo "files: $(ls -1 "$CACHE" 2>/dev/null | wc -l) ($(du -sh "$CACHE" 2>/dev/null | cut -f1))"
else
	echo "no cache dir under $SUC/pyroveil"
fi

echo
echo "=== recent Xid (NVIDIA driver faults) ==="
dmesg --time-format iso 2>/dev/null | grep -i xid | tail -5 || echo "dmesg needs root"
