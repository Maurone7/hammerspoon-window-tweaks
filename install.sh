#!/bin/sh
# Installs the Spoons into ~/.hammerspoon/Spoons.
# Pass --link to symlink them instead of copying, so `git pull` updates them.
set -eu

src="$(cd "$(dirname "$0")" && pwd)/Spoons"
dest="$HOME/.hammerspoon/Spoons"
mode=copy
[ "${1:-}" = "--link" ] && mode=link

mkdir -p "$dest"
for spoon in "$src"/*.spoon; do
  name=$(basename "$spoon")
  rm -rf "${dest:?}/$name"
  if [ "$mode" = link ]; then
    ln -s "$spoon" "$dest/$name"
  else
    cp -R "$spoon" "$dest/"
  fi
  echo "Installed $name ($mode)"
done

cat <<'EOF'

Now add the ones you want to ~/.hammerspoon/init.lua:

  hs.loadSpoon("FullscreenTrafficLights"):start()
  hs.loadSpoon("FinderCut"):start()
  hs.loadSpoon("ClickThrough"):start()

then choose "Reload Config" from the Hammerspoon menu.
EOF
