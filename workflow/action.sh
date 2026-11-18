#!/bin/zsh -f
# action.sh — Run Script action for Alfred Kill. Prints one line for Alfred's
# notification.
#
#   action.sh "term  <pid>@<start>"   SIGTERM, wait, SIGKILL if still alive (↩)
#   action.sh "force <pid>@<start>"   SIGKILL now (⌥↩)
#   action.sh "all   <pid>@<start>"   quit every process with that executable (⌘↩)
#   action.sh "update_check [now]" | "update_install X.Y.Z"
#
# Before any signal, the PID's current start time must equal the one captured
# when the list was drawn, so a PID reused by another process is never hit.

source "${0:A:h}/lib/common.zsh"
source $KP_WF_DIR/lib/procs.zsh

(( $# == 1 )) && set -- ${(z)1}
typeset verb=${1:-} target=${2:-}

case $verb in
  update_check|update_install)
    source $KP_WF_DIR/lib/update.zsh
    if [[ $verb == update_check ]]; then update_cmd_check $target; else update_cmd_install $target; fi
    exit ;;
  term|force|all) ;;
  *) print "Unknown action"; exit 64 ;;
esac

# Target must be <digits>@<start token> and nothing else.
if ! [[ $target == (#b)(<->)@([A-Za-z0-9_:]##) && $# == 2 ]]; then
  print "Invalid process reference"; exit 64
fi
typeset -i PID=$match[1]
typeset TOK=$match[2]
protected $PID && { print "PID $PID is protected: not killed"; exit 64 }

# lookup PID → REC_UID REC_TOK REC_EXE from a fresh process list.
typeset REC_UID= REC_TOK= REC_EXE=
lookup() {
  local r; local -a f
  for r in $PROCS; do
    f=("${(@ps:\t:)r}")
    [[ $f[1] == $1 ]] || continue
    REC_UID=$f[2] REC_TOK=$f[5] REC_EXE=$f[6]
    return 0
  done
  return 1
}

# quit PID TOKEN → 0 quit, 2 force-killed, 1 failed. Re-checks identity
# before the SIGKILL in case the PID was reused while waiting.
quit() {
  local pid=$1 tok=$2
  $KILL -TERM $pid 2>/dev/null || return 1
  integer i
  for (( i = 0; i < WAIT_STEPS; i++ )); do
    $KILL -0 $pid 2>/dev/null || return 0
    sleep 0.1
  done
  $KILL -0 $pid 2>/dev/null || return 0
  current_token $pid && [[ $REPLY == $tok ]] || return 0
  $KILL -KILL $pid 2>/dev/null && return 2
  return 1
}

list_procs
if ! lookup $PID; then print "PID $PID has already exited"; exit 1; fi
if [[ $REC_TOK != $TOK ]]; then print "PID $PID is now a different process: nothing was killed"; exit 1; fi
typeset NAME=${REC_EXE:t}
if (( REC_UID != MY_UID )); then print "$NAME (PID $PID) is owned by $(owner_name $REC_UID): not killed"; exit 1; fi

case $verb in
  force)
    if $KILL -KILL $PID 2>/dev/null; then print "Force-killed $NAME (PID $PID)"
    else print "Could not kill $NAME (PID $PID)"; exit 1; fi ;;
  term)
    quit $PID $TOK
    case $? in
      0) print "Quit $NAME (PID $PID)" ;;
      2) print "Force-killed $NAME (PID $PID): it did not quit in time" ;;
      *) print "Could not kill $NAME (PID $PID)"; exit 1 ;;
    esac ;;
  all)
    # Every process of this user running the same binary. ps shows argv[0],
    # which processes choose themselves, so the real binary of the target and
    # of each candidate comes from lsof. Candidates are pre-filtered by name to
    # keep the lsof calls few. Each is signalled in parallel, then waited for.
    real_exe $PID || { print "Could not resolve the program of $NAME (PID $PID): nothing was killed"; exit 1 }
    local bin=$REPLY
    local -a pids=() toks=()
    local r; local -a f
    for r in $PROCS; do
      f=("${(@ps:\t:)r}")
      [[ $f[2] == $MY_UID ]] || continue
      [[ ${f[6]:t} == (${(b)NAME}|${(b)bin:t}) ]] || continue
      protected $f[1] && continue
      real_exe $f[1] && [[ $REPLY == $bin ]] || continue
      pids+=($f[1]) toks+=($f[5])
    done
    integer n=0 forced=0 failed=0 i
    local dir=$(mktemp -d)
    for (( i = 1; i <= $#pids; i++ )); do
      { quit $pids[i] $toks[i]; print $? > $dir/$pids[i] } &
    done
    wait
    for (( i = 1; i <= $#pids; i++ )); do
      case $(<$dir/$pids[i]) in
        0) (( ++n )) ;;
        2) (( ++n, ++forced )) ;;
        *) (( ++failed )) ;;
      esac
    done
    rm -rf -- $dir
    local msg="Quit $n × $NAME"
    (( forced )) && msg+=" ($forced force-killed)"
    (( failed )) && msg+=", $failed could not be killed"
    print -r -- $msg ;;
esac
