#!/bin/zsh
# Removes Wakeful, its watchdog, its sudoers rule and its saved state.
setopt no_unset pipe_fail

app="${APP_DIR:-/Applications}/Wakeful.app"
label=local.wakeful.watchdog
agent="$HOME/Library/LaunchAgents/$label.plist"
sudoers=/etc/sudoers.d/wakeful
state_dir="$HOME/Library/Application Support/Wakeful"

source "${0:A:h}/as-root.zsh"

if pgrep -x Wakeful >/dev/null; then
  pkill -TERM -x Wakeful
  for _ in {1..25}; do pgrep -x Wakeful >/dev/null || break; sleep 0.2; done
fi

# A leftover record means Wakeful's flag may still be on.
revert=""
if [[ -f "$state_dir/lid-session.json" ]]; then
  revert="/usr/bin/pmset -a disablesleep 0; "
fi

launchctl bootout "gui/$UID/$label" 2>/dev/null
rm -f "$agent"
as_root "${revert}rm -f $sudoers" || echo "Could not remove $sudoers; remove it with: sudo rm $sudoers" >&2
rm -rf "$app" "$state_dir" "$HOME/Library/Logs/Wakeful"
defaults delete local.wakeful.app 2>/dev/null
echo "Wakeful is uninstalled."
