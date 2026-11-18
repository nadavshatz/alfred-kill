# lib/common.zsh — shared helpers for Alfred Kill.
#
# Alfred Script Filter JSON, configuration and tool paths. System tools are
# reached through KP_* variables so the test-suite can substitute mocks.
# Nothing here ever passes a string to eval or sh -c.

zmodload zsh/datetime
setopt extended_glob no_unset pipe_fail
umask 077

typeset -r KP_LABEL="io.github.nadavshatz.kill"
typeset -r KP_WF_DIR="${${(%):-%x}:A:h:h}"          # .../workflow

typeset -r PS="${KP_PS:-/bin/ps}"
typeset -r KILL="${KP_KILL:-/bin/kill}"
typeset -r LSOF="${KP_LSOF:-/usr/sbin/lsof}"
typeset -ri MY_UID="${KP_UID:-$UID}"
typeset -ri WAIT_STEPS="${KP_WAIT_STEPS:-20}"     # × 0.1s before SIGKILL

# Updater (lib/update.zsh)
typeset -r UPD_LABEL=$KP_LABEL UPD_NAME="Alfred Kill" UPD_PKG="Alfred-Kill" UPD_WF_DIR=$KP_WF_DIR
typeset -r UPD_REPO="${KP_UPDATE_REPO:-https://github.com/nadavshatz/alfred-kill}"
typeset -r UPD_CURL="${KP_CURL:-/usr/bin/curl}" UPD_OPEN="${KP_OPEN:-/usr/bin/open}"

# ---------------------------------------------------------------------------
# Alfred JSON
# ---------------------------------------------------------------------------
typeset -ga ITEMS=()

js() {  # JSON string literal
  local s=${1-}
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//[[:cntrl:]]/}
  print -rn -- "\"$s\""
}

# item TITLE SUBTITLE ARG VALID ICON [key=value ...]
#   ICON: a name under icons/ (no extension), or fileicon:/path/to/App.app
#   cmd=ARG alt=ARG   modifier args (fixed subtitles)
#   ac=STR uid=STR    autocomplete / Alfred learning uid
item() {
  local t=$1 sub=$2 arg=$3 valid=$4 icon=$5; shift 5
  local j="{\"title\":$(js "$t"),\"subtitle\":$(js "$sub"),\"arg\":$(js "$arg"),\"valid\":$valid"
  if [[ $icon == fileicon:* ]]; then
    j+=",\"icon\":{\"type\":\"fileicon\",\"path\":$(js "${icon#fileicon:}")}"
  else
    j+=",\"icon\":{\"path\":$(js "icons/$icon.png")}"
  fi
  local -a mods=()
  local kv k v
  for kv in "$@"; do
    k=${kv%%=*} v=${kv#*=}
    case $k in
      cmd) mods+=("\"cmd\":{\"arg\":$(js "$v"),\"subtitle\":\"Quit every process with this name (yours only)\",\"valid\":true}") ;;
      alt) mods+=("\"alt\":{\"arg\":$(js "$v"),\"subtitle\":\"Force kill now (SIGKILL)\",\"valid\":true}") ;;
      ac)  j+=",\"autocomplete\":$(js "$v")" ;;
      uid) j+=",\"uid\":$(js "$v")" ;;
    esac
  done
  if (( $#mods )); then
    j+=",\"mods\":{${(j:,:)mods}}"
  elif [[ $valid == true ]]; then
    # No connection-level fallbacks: modifiers do nothing on other items.
    j+=",\"mods\":{\"cmd\":{\"valid\":false,\"subtitle\":\"\"},\"alt\":{\"valid\":false,\"subtitle\":\"\"}}"
  fi
  ITEMS+=("$j}")
}

emit() { print -r -- "{\"skipknowledge\":true,\"items\":[${(j:,:)ITEMS}]}" }
