#!/bin/zsh -f
# filter.sh — Alfred Kill Script Filter.
#
#   kill <name>        fuzzy-match running processes by executable name
#   kill <name>:<arg>  …and keep those whose command line contains <arg>
#
# Item args: "term <pid>@<start>" (↩), "force …" (⌥), "all …" (⌘).
# The query is only ever compared literally; it never reaches a command.

source "${0:A:h}/lib/common.zsh"
source $KP_WF_DIR/lib/procs.zsh
typeset -i HAS_UPDATER=0
[[ -r $KP_WF_DIR/lib/update.zsh ]] && source $KP_WF_DIR/lib/update.zsh && HAS_UPDATER=1

typeset -ri MAX_ITEMS=30
typeset Q=${${1:-}##[[:space:]]#}
Q=${Q%%[[:space:]]#}
typeset NAMEQ=$Q ARGQ=
if [[ $Q == *:* ]]; then NAMEQ=${Q%%:*} ARGQ=${Q#*:}; fi
typeset -r NQ=${(L)NAMEQ} AQ=${(L)ARGQ}

# score NAME → REPLY (lower is better); 1 = no match. Literal comparisons;
# the subsequence pattern quotes each character before joining with *.
score() {
  local n=${(L)1} q=$NQ
  if   [[ -z $q ]];         then REPLY=5
  elif [[ $n == $q ]];      then REPLY=0
  elif [[ $n == ${q}* ]];   then REPLY=1
  elif [[ $n == *${q}* ]];  then REPLY=2
  else
    local pat=${(j:*:)${(@b)${(s::)q}}}
    [[ $n == *${~pat}* ]] || return 1
    REPLY=3
  fi
}

# matched_arg PID → REPLY=first command-line word containing ARGQ.
matched_arg() {
  REPLY=
  local w
  for w in ${(z)"$(proc_args $1)"}; do
    [[ ${(L)w} == *${AQ}* ]] && { REPLY=$w; return 0 }
  done
  return 1
}

list_procs
typeset -a ranked=()
typeset r pid uid pcpu rss tok exe name
typeset -a f
for r in $PROCS; do
  f=("${(@ps:\t:)r}"); pid=$f[1] uid=$f[2] pcpu=$f[3] rss=$f[4] tok=$f[5] exe=$f[6]
  protected $pid && continue
  name=${exe:t}
  [[ -n $name ]] || continue
  score "$name" || continue
  # Sort key: score, then CPU (descending, as an inverted fixed-width number), then name.
  ranked+=("$REPLY"$'\t'"${(l:7::0:)$(( 1000000 - ${pcpu%.*} * 10 - ${${pcpu#*.}[1]:-0} ))}"$'\t'"$r")
done
ranked=(${(o)ranked})

[[ -z $Q ]] && item "Kill a process" "Type a name · name:arg filters by command line · ↩ quit · ⌥ force · ⌘ all with that name" "" false icon

integer shown=0
typeset label sub icon
for r in $ranked; do
  (( shown >= MAX_ITEMS )) && break
  f=("${(@ps:\t:)r}"); pid=$f[3] uid=$f[4] pcpu=$f[5] rss=$f[6] tok=$f[7] exe=$f[8]
  name=${exe:t} label=$name
  if [[ -n $AQ ]]; then
    matched_arg $pid || continue
    label="$name $REPLY"
  fi
  sub="${pcpu}% CPU · $(fmt_mem $rss) · PID $pid · $exe"
  icon=$(app_icon "$exe")
  if (( uid == MY_UID )); then
    item "$label" "$sub" "term $pid@$tok" true "$icon" alt="force $pid@$tok" cmd="all $pid@$tok" uid="$exe" ac="$name"
  else
    item "$label" "Owned by $(owner_name $uid), not killable without sudo · $sub" "" false "$icon"
  fi
  (( ++shown ))
done

(( shown )) || item "No process matches “$Q”" "Type part of a process name, e.g. chrome or node:server.js" "" false info
[[ -z $Q ]] && (( HAS_UPDATER )) && update_notice "$KP_WF_DIR/action.sh"
emit
