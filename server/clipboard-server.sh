#!/usr/bin/env bash
# Private, authenticated X11 clipboard for the current Linux user.
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export PATH="$script_dir:$HOME/.local/bin:$PATH"
display=:99
command_name=ensure
while (($#)); do
    case "$1" in
        --display) display=${2:?Missing display}; shift 2 ;;
        ensure|status|put|get|save|stop|self-test) command_name=$1; shift ;;
        -h|--help) echo "Usage: $0 [--display :99] {ensure|status|put|get|save|stop|self-test}"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ $display =~ ^:[0-9]+$ ]] || { echo 'Display must look like :99.' >&2; exit 2; }
state_root=${SSH_IMAGE_PASTE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ssh-image-paste}
state="$state_root/display-${display#:}"
mkdir -p "$state"
chmod 700 "$state"
export DISPLAY=$display XAUTHORITY="$state/Xauthority"
pidfile="$state/Xvfb.pid"

die() { printf 'ssh-image-paste: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null || die "Missing dependency: $1 (see README)."; }
if [[ $command_name != save ]]; then
    for tool in Xvfb xclip xauth xdpyinfo timeout flock openssl; do require "$tool"; done
fi
ready() { timeout 2 xdpyinfo >/dev/null 2>&1; }
owned_pid() {
    local pid
    [[ -f $pidfile ]] || return 1
    read -r pid < "$pidfile"
    [[ $pid =~ ^[0-9]+$ && -O /proc/$pid ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    # Match our exact authority file rather than an unrelated process name.
    tr '\0' '\n' < "/proc/$pid/cmdline" | grep -Fxq -- "$XAUTHORITY" || return 1
    printf '%s\n' "$pid"
}
ensure_server() (
    exec 9>"$state/lifecycle.lock"
    flock -w 12 9 || die 'Another start/stop operation is still running.'
    if owned_pid >/dev/null; then
        for _ in {1..20}; do ready && exit 0; sleep 0.1; done
        die "Managed Xvfb is not responding; inspect $state/Xvfb.log."
    fi
    # Never take over someone else's display, even if it happens to be readable.
    [[ ! -S /tmp/.X11-unix/X${display#:} ]] || die "$display is already in use or has a stale socket. Choose another display; do not delete other users' sockets."
    if [[ ! -s $XAUTHORITY ]]; then
        touch "$XAUTHORITY"
        cookie=$(openssl rand -hex 16)
        printf 'add %s MIT-MAGIC-COOKIE-1 %s\n' "$display" "$cookie" | xauth -f "$XAUTHORITY" >/dev/null
        unset cookie
        chmod 600 "$XAUTHORITY"
    fi
    nohup Xvfb "$display" -screen 0 1x1x24 -nolisten tcp -auth "$XAUTHORITY" \
        </dev/null >>"$state/Xvfb.log" 2>&1 9>&- &
    new_pid=$!
    printf '%s\n' "$new_pid" > "$pidfile"
    for _ in {1..30}; do
        ready && exit 0
        kill -0 "$new_pid" 2>/dev/null || break
        sleep 0.1
    done
    die "Cannot start $display. Inspect $state/Xvfb.log."
)
read_png() {
    input=$(mktemp "$state/input.XXXXXXXX.png")
    trap 'rm -f -- "${input:-}" "${output:-}"' EXIT
    cat > "$input"
    signature=$(od -An -tx1 -N8 "$input" | tr -d ' \n')
    [[ $signature == 89504e470d0a1a0a ]] || die 'Input is not a PNG image.'
    [[ $(wc -c < "$input") -le 67108864 ]] || die 'PNG exceeds the 64 MiB limit.'
}

case "$command_name" in
    ensure) ensure_server ;;
    status)
        printf 'DISPLAY=%s\nXAUTHORITY=%s\n' "$DISPLAY" "$XAUTHORITY"
        owned_pid >/dev/null && ready || die 'Managed clipboard display is not running.'
        printf 'Xvfb=ready\n'
        timeout 3 xclip -selection clipboard -t TARGETS -o 2>/dev/null || true
        ;;
    put)
        ensure_server
        read_png
        # xclip forks a selection owner. Detach every inherited SSH stream.
        xclip -selection clipboard -t image/png -i < "$input" >/dev/null 2>&1
        printf 'OK\n'
        ;;
    get)
        ensure_server
        timeout 5 xclip -selection clipboard -t image/png -o
        ;;
    save)
        read_png
        directory="${XDG_CACHE_HOME:-$HOME/.cache}/ssh-image-paste/images"
        mkdir -p "$directory"
        chmod 700 "$directory"
        destination=$(mktemp "$directory/clip-XXXXXXXX.png")
        cp -- "$input" "$destination"
        chmod 600 "$destination"
        printf '%s\n' "$destination"
        ;;
    stop)
        exec 9>"$state/lifecycle.lock"
        flock -w 12 9 || die 'Another start/stop operation is running.'
        if pid=$(owned_pid); then
            kill "$pid"
            for _ in {1..30}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
            rm -f -- "$pidfile"
        fi
        ;;
    self-test)
        ensure_server
        input=$(mktemp "$state/self-test.XXXXXXXX.png")
        output=$(mktemp "$state/read-back.XXXXXXXX.png")
        trap 'rm -f -- "$input" "$output"' EXIT
        # A valid 1x1 PNG fixture. This replaces the current remote clipboard.
        printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' | base64 -d > "$input"
        xclip -selection clipboard -t image/png -i < "$input" >/dev/null 2>&1
        timeout 5 xclip -selection clipboard -t image/png -o > "$output"
        cmp "$input" "$output" || die 'Clipboard round trip changed the PNG.'
        echo 'PASS: PNG clipboard round trip is byte-for-byte identical.'
        ;;
esac
