#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temporary=$(mktemp -d)
display=${TEST_DISPLAY:-:199}
helper="$temporary/prefix/bin/ssh-image-paste-server"
export SSH_IMAGE_PASTE_STATE_DIR="$temporary/state"
export XDG_CACHE_HOME="$temporary/cache"
cleanup() {
    if [[ -x $helper ]]; then "$helper" --display "$display" stop >/dev/null 2>&1 || true; fi
    rm -rf -- "$temporary"
}
trap cleanup EXIT
bash -n "$root/server/clipboard-server.sh" "$root/server/setup.sh"
bash "$root/server/setup.sh" --display "$display" --prefix "$temporary/prefix" --config-dir "$temporary/config" --state-dir "$temporary/state"
# Idempotent setup/start and concurrent starts must retain one managed X server.
original_pid=$(cat "$temporary/state/display-${display#:}/Xvfb.pid")
bash "$root/server/setup.sh" --display "$display" --prefix "$temporary/prefix" --config-dir "$temporary/config" --state-dir "$temporary/state" >/dev/null
jobs=()
for _ in {1..4}; do "$helper" --display "$display" ensure & jobs+=("$!"); done
for job in "${jobs[@]}"; do wait "$job"; done
[[ $(cat "$temporary/state/display-${display#:}/Xvfb.pid") == "$original_pid" ]]
cp "$temporary/config/env.sh" "$temporary/environment.before"
if bash "$root/server/setup.sh" --display "$display" --prefix "$temporary/prefix" --config-dir "$temporary/config" --state-dir "$temporary/collision-state" >/dev/null 2>&1; then
    echo 'FAIL: conflicting setup unexpectedly succeeded.' >&2; exit 1
fi
cmp "$temporary/environment.before" "$temporary/config/env.sh"
"$helper" --display "$display" self-test
"$helper" --display "$display" get > "$temporary/first.png"
if printf 'not an image' | "$helper" --display "$display" put 2>/dev/null; then
    echo 'FAIL: invalid PNG was accepted.' >&2; exit 1
fi
"$helper" --display "$display" get > "$temporary/after-invalid.png"
cmp "$temporary/first.png" "$temporary/after-invalid.png"
path=$("$helper" --display "$display" save < "$temporary/first.png")
cmp "$temporary/first.png" "$path"
[[ $(stat -c %a "$path") == 600 ]]
[[ $(stat -c %a "$temporary/state/display-${display#:}/Xauthority") == 600 ]]
# An unrelated state directory must never adopt the running display.
if SSH_IMAGE_PASTE_STATE_DIR="$temporary/other" "$helper" --display "$display" ensure 2>/dev/null; then
    echo 'FAIL: adopted a foreign display.' >&2; exit 1
fi
# Confirm the X server actually enforces the private authentication file.
if timeout 3 env DISPLAY="$display" XAUTHORITY=/dev/null xdpyinfo >/dev/null 2>&1; then
    echo 'FAIL: unauthenticated X11 connection was allowed.' >&2; exit 1
fi
"$helper" --display "$display" stop
"$helper" --display "$display" ensure
"$helper" --display "$display" status
echo 'PASS: setup, concurrent start, PNG round trip, invalid input, file permissions, X11 authentication, collision refusal, restart.'
