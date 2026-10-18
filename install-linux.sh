#!/usr/bin/env bash
# Install DwarfTalk into a Steam DFHack on Linux.
# - symlinks the Lua scripts into dfhack-config/scripts/dwarftalk (edits apply live)
# - adds keybindings to dfhack.init and the startup hook to onMapLoad.init
# Re-running is safe; uninstall with: ./install-linux.sh --uninstall
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
# Steam DFHack on Linux reads its config from the *Dwarf Fortress* folder
# (launchdf injects it there), not from the separate DFHack app folder.
DF="${DF_DIR:-$HOME/.local/share/Steam/steamapps/common/Dwarf Fortress}"
CFG="$DF/dfhack-config"
[ -d "$CFG" ] || { echo "DFHack config not found at $CFG - launch DFHack from Steam once, or set DF_DIR"; exit 1; }

BEGIN="# >>> dwarftalk >>>"
END="# <<< dwarftalk <<<"

strip_block() { # file
    [ -f "$1" ] && sed -i "/^$BEGIN\$/,/^$END\$/d" "$1" || true
}

strip_block "$CFG/init/dfhack.init"
strip_block "$CFG/init/onMapLoad.init"
rm -f "$CFG/scripts/dwarftalk"

if [ "${1:-}" = "--uninstall" ]; then
    echo "DwarfTalk removed from $CFG"
    exit 0
fi

mkdir -p "$CFG/scripts"
ln -s "$REPO/workshop/scripts_modinstalled/dwarftalk" "$CFG/scripts/dwarftalk"

cat >> "$CFG/init/dfhack.init" <<KEYS
$BEGIN
keybinding add Ctrl-T@dwarfmode dwarftalk/chat_window
keybinding add Alt-Shift-S@dwarfmode dwarftalk/settings_window
$END
KEYS

cat >> "$CFG/init/onMapLoad.init" <<HOOK
$BEGIN
dwarftalk/init
repeat --name dwarftalk_autostart --time 250 --timeUnits ticks --command [ dwarftalk/daemon_check ]
$END
HOOK

echo "DwarfTalk installed into $CFG"
echo "  scripts -> $CFG/scripts/dwarftalk"
echo "  Ctrl-T: chat   Alt-Shift-S: settings"
