# Runs a /bin/sh command as root: through sudo when there is a terminal to ask for the
# password, otherwise through the macOS admin password dialog.
# Keep double quotes and backslashes out of the command; it is embedded in AppleScript.
as_root() {
  local cmd=$1
  if [[ -t 0 ]] || sudo -n true 2>/dev/null; then
    sudo /bin/sh -c "$cmd"
  else
    osascript -e "do shell script \"$cmd\" with administrator privileges" >/dev/null
  fi
}
