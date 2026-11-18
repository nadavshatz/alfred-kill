# lib/procs.zsh — read the process table.
#
# One `ps` call lists every process with PID, owner, CPU, memory, start time
# and executable path. The start time doubles as an identity token: a PID
# plus its start time names exactly one process, so a PID that was reused
# after the list was drawn is detected before anything is signalled.

# list_procs → PROCS=("pid\tuid\tpcpu\trss\tstart-token\tpath" ...)
typeset -ga PROCS=()
list_procs() {
  PROCS=()
  local line
  for line in ${(f)"$(ps_c -A -o pid=,uid=,pcpu=,rss=,lstart=,comm= 2>/dev/null)"}; do
    [[ $line == (#b)[[:space:]]#(<->)[[:space:]]##(-#<->)[[:space:]]##([0-9.,]##)[[:space:]]##(<->)[[:space:]]##([A-Z][a-z][a-z][[:space:]]##[A-Z][a-z][a-z][[:space:]]##[0-9]##[[:space:]]##[0-9:]##[[:space:]]##[0-9](#c4))[[:space:]]##(*) ]] || continue
    PROCS+=("$match[1]"$'\t'"$match[2]"$'\t'"${match[3]/,/.}"$'\t'"$match[4]"$'\t'"${${match[5]//[[:space:]]##/_}%%_#}"$'\t'"$match[6]")
  done
}

# start_token "Tue Nov 10 20:24:09 2026" → Tue_Nov_10_20:24:09_2026
start_token() { print -r -- ${${1//[[:space:]]##/_}%%_#} }

# current_token PID → REPLY=start token of the live process (1 if gone).
current_token() {
  REPLY=
  local s
  s=$(ps_c -p $1 -o lstart= 2>/dev/null) || return 1
  [[ -n ${s//[[:space:]]/} ]] || return 1
  REPLY=$(start_token "${s##[[:space:]]#}")
}

# proc_path PID → REPLY=executable path of the live process.
proc_path() {
  REPLY=
  local p
  p=$(ps_c -p $1 -o comm= 2>/dev/null) || return 1
  REPLY=${${p##[[:space:]]#}%%[[:space:]]#}
  [[ -n $REPLY ]]
}

proc_args() { ps_c -p $1 -o args= 2>/dev/null }

# protected PID: never offered or signalled.
protected() { (( $1 <= 1 || $1 == $$ || $1 == PPID )) }

# owner_name UID
owner_name() { (( $1 == 0 )) && print root || print "uid $1" }

# fmt_mem KB
fmt_mem() {
  integer kb=$1
  if (( kb >= 1048576 )); then printf '%.1f GB' $(( kb / 1048576.0 ))
  elif (( kb >= 1024 )); then print "$(( kb / 1024 )) MB"
  else print "$kb KB"; fi
}

# app_icon PATH → icon spec: innermost .app bundle, else the bundled icon.
app_icon() {
  if [[ $1 == *.app/* ]]; then print -r -- "fileicon:${1%.app/*}.app"
  else print process; fi
}

# ps_c ARGS…: ps with a fixed C locale, so the start time and CPU columns
# always have the format list_procs parses (LC_ALL=de_DE prints "Di. 10 Nov.").
ps_c() { LC_ALL=C $PS "$@" }

# all_args → ARGS[pid]=command line, from a single ps call.
typeset -gA ARGS=()
all_args() {
  ARGS=()
  local line
  for line in ${(f)"$(ps_c -A -o pid=,args= 2>/dev/null)"}; do
    [[ $line == (#b)[[:space:]]#(<->)[[:space:]]##(*) ]] && ARGS[$match[1]]=$match[2]
  done
}

# real_exe PID → REPLY=the binary the process is actually running. `ps -o
# comm=` shows argv[0], which any process can set; lsof's txt entry can't be.
real_exe() {
  REPLY=
  local line
  for line in ${(f)"$($LSOF -n -P -p $1 -a -d txt -Fn 2>/dev/null)"}; do
    [[ $line == n/* ]] && { REPLY=${line#n}; return 0 }
  done
  return 1
}
