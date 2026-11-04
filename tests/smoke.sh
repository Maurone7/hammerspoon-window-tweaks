#!/bin/sh
# Smoke test on a real Mac: reloads Hammerspoon and checks that the installed
# Spoons are loaded and working. Reads state only; it never clicks or types.
# Needs Hammerspoon running with `require("hs.ipc")` in ~/.hammerspoon/init.lua.
set -eu

dir="$(cd "$(dirname "$0")" && pwd)"

if ! command -v hs >/dev/null 2>&1; then
  echo "The hs command isn't installed. Add require(\"hs.ipc\") to ~/.hammerspoon/init.lua and reload." >&2
  exit 1
fi

wait_for_hammerspoon() {
  i=0
  until hs -c 'print(1)' >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -gt 40 ]; then
      echo "Hammerspoon isn't responding. Is it running?" >&2
      exit 1
    fi
    sleep 0.5
  done
}

wait_for_hammerspoon
# Errors are only looked for in console text added after this point.
console_start=$(hs -c 'print(#hs.console.getConsole())' | tail -n 1)
hs -c 'hs.reload()' >/dev/null 2>&1 || true
sleep 1
wait_for_hammerspoon
sleep 1

output=$(hs -c "SMOKE_CONSOLE_START = $console_start; dofile('$dir/smoke.lua')")
echo "$output"
case "$output" in
  *"smoke test passed"*) exit 0 ;;
  *) exit 1 ;;
esac
