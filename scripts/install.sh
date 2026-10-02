#!/bin/zsh
# Builds Wakeful, installs it, and sets up lid-closed mode:
#   - a sudoers rule that allows only `pmset -a disablesleep 0|1` for this user
#   - a LaunchAgent watchdog that turns the flag off if Wakeful dies or overruns
# Asks for your admin password once, for the sudoers rule (a macOS dialog when there is no terminal).
setopt err_exit no_unset pipe_fail

root=${0:A:h:h}
app_dir=${APP_DIR:-/Applications}
app="$app_dir/Wakeful.app"
label=local.wakeful.watchdog
agent="$HOME/Library/LaunchAgents/$label.plist"
sudoers=/etc/sudoers.d/wakeful
user=$(id -un)

source "$root/scripts/as-root.zsh"

make -C "$root" app

# Quitting through SIGTERM makes Wakeful turn off its own flag first.
if pgrep -x Wakeful >/dev/null; then
  echo "Quitting the running Wakeful…"
  pkill -TERM -x Wakeful || true
  for _ in {1..25}; do pgrep -x Wakeful >/dev/null || break; sleep 0.2; done
fi

echo "Installing $app"
rm -rf "$app"
ditto "$root/build/Wakeful.app" "$app"

if [[ -f "$sudoers" ]] && sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1; then
  echo "The sudoers rule at $sudoers is already in place"
else
  echo "Installing the sudoers rule at $sudoers (admin password needed)"
  rule_file=$(mktemp)
  trap 'rm -f "$rule_file"' EXIT
  print -r -- "$user ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$rule_file"
  /usr/sbin/visudo -cqf "$rule_file"
  chmod 0644 "$rule_file"
  # One privileged step, so there is a single password prompt. If the full sudoers
  # configuration fails validation afterwards, the rule is removed again.
  if ! as_root "install -m 0440 -o root -g wheel '$rule_file' '$sudoers' && /usr/sbin/visudo -cq || { rm -f '$sudoers'; exit 1; }"; then
    echo "Installing the sudoers rule failed or was cancelled; nothing was changed." >&2
    exit 1
  fi
fi

echo "Installing the watchdog LaunchAgent at $agent"
mkdir -p "${agent:h}" "$HOME/Library/Logs/Wakeful"
cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$label</string>
	<key>ProgramArguments</key>
	<array>
		<string>$app/Contents/MacOS/wakeful-watchdog</string>
	</array>
	<key>StartInterval</key>
	<integer>60</integer>
	<key>RunAtLoad</key>
	<true/>
	<key>ProcessType</key>
	<string>Background</string>
	<key>StandardErrorPath</key>
	<string>$HOME/Library/Logs/Wakeful/watchdog.log</string>
</dict>
</plist>
PLIST
launchctl bootout "gui/$UID/$label" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$agent"

open "$app"
echo "Done. Wakeful is in the menu bar."
