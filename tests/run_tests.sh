#!/bin/zsh -f
# Alfred Kill test-suite. Runs on macOS or Linux with zsh + jq; ps, kill, curl
# and open are mocked (tests/mocks) and no real process is ever signalled.
#
#   zsh tests/run_tests.sh

setopt extended_glob no_unset
ROOT=${0:A:h:h}
WF=$ROOT/workflow
SANDBOX=$(mktemp -d)
trap 'rm -rf $SANDBOX' EXIT

export MOCK_DIR=$SANDBOX/mock
export KP_PS=$ROOT/tests/mocks/ps KP_KILL=$ROOT/tests/mocks/kill KP_UID=501 KP_WAIT_STEPS=3
export KP_CURL=$ROOT/tests/mocks/curl KP_OPEN=$ROOT/tests/mocks/open
export alfred_workflow_cache=$SANDBOX/cache alfred_workflow_data=$SANDBOX/data
export alfred_workflow_version=1.0.0 update_mode=off
mkdir -p $MOCK_DIR

integer pass=0 fail=0
ok()   { print -P "%F{green}✔%f $1"; (( ++pass )) }
bad()  { print -P "%F{red}✘ $1%f"; [[ -n ${2:-} ]] && print -r -- "   $2"; (( ++fail )) }
check() { local d=$1; shift; if "$@"; then ok $d; else bad $d; fi }

T1='Tue Nov 10 20:24:09 2026'
T2='Wed Nov 18 09:00:00 2026'
fixtures() {
  rm -rf $MOCK_DIR; mkdir -p $MOCK_DIR
  {
    print -r -- "1	0	0.5	25000	$T1	/sbin/launchd	/sbin/launchd"
    print -r -- "300	0	1.0	9000	$T1	/usr/sbin/syslogd	/usr/sbin/syslogd"
    print -r -- "4100	501	12.5	524288	$T2	/Applications/Google Chrome.app/Contents/MacOS/Google Chrome	/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    print -r -- "4200	501	3.0	102400	$T2	/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper	Google Chrome Helper --type=renderer"
    print -r -- "4201	501	2.0	51200	$T2	/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper	Google Chrome Helper --type=gpu-process"
    print -r -- "5000	501	0.0	2048	$T2	/opt/homebrew/bin/node	node /Users/me/app/server.js --port=3000"
    print -r -- "5001	501	0.0	2048	$T2	/opt/homebrew/bin/node	node /Users/me/other/worker.js"
    print -r -- "6000	501	0.0	1024	$T2	/tmp/we(ird) [x]|y	/tmp/we(ird) [x]|y"
  } > $MOCK_DIR/procs
}
filter() { $WF/filter.sh "${1:-}" }
titles() { filter "${1:-}" | jq -r '.items[].title' }
TOK2=${T2// /_}

# --- filter ----------------------------------------------------------------------
fixtures
out=$(filter chrome)
check "filter emits valid JSON" eval 'print -r -- $out | jq -e . >/dev/null'
check "exact name ranks first" eval '[[ $(print -r -- $out | jq -r ".items[0].title") == "Google Chrome" ]]'
check "helpers listed too" eval '[[ $(print -r -- $out | jq "[.items[] | select(.title==\"Google Chrome Helper\")] | length") == 2 ]]'
check "↩ arg is 'term pid@start'" eval '[[ $(print -r -- $out | jq -r ".items[0].arg") == "term 4100@$TOK2" ]]'
check "⌥ arg is 'force pid@start'" eval '[[ $(print -r -- $out | jq -r ".items[0].mods.alt.arg") == "force 4100@$TOK2" ]]'
check "⌘ arg is 'all pid@start'" eval '[[ $(print -r -- $out | jq -r ".items[0].mods.cmd.arg") == "all 4100@$TOK2" ]]'
check "subtitle shows CPU, memory, PID, path" \
  eval '[[ $(print -r -- $out | jq -r ".items[0].subtitle") == "12.5% CPU · 512 MB · PID 4100 · /Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]'
check "app process uses the .app file icon" \
  eval '[[ $(print -r -- $out | jq -r ".items[0].icon | [.type,.path] | @tsv") == "fileicon	/Applications/Google Chrome.app" ]]'
check "helper uses its own innermost .app icon" \
  eval '[[ $(print -r -- $out | jq -r ".items[1].icon.path") == "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app" ]]'
check "plain binary uses the bundled icon" eval '[[ $(filter node | jq -r ".items[0].icon.path") == icons/process.png ]]'
check "case-insensitive" eval '[[ $(titles CHROME | head -1) == "Google Chrome" ]]'
check "subsequence match: 'gch' → Google Chrome" eval '[[ $(titles gch) == *"Google Chrome"* ]]'

out=$(filter syslog)
check "root process listed but not actionable" \
  eval '[[ $(print -r -- $out | jq -r ".items[0] | [.title,.valid] | @tsv") == "syslogd	false" ]]'
check "root process subtitle explains" eval '[[ $(print -r -- $out | jq -r ".items[0].subtitle") == *"Owned by root"* ]]'
check "launchd (PID 1) never listed" eval '[[ $(filter launchd | jq "[.items[] | select(.title==\"launchd\")] | length") == 0 ]]'

out=$(filter 'node:3000')
check "name:arg keeps only matching command lines" eval '[[ $(print -r -- $out | jq -r "[.items[].arg] | join(\" \")") == "term 5000@$TOK2" ]]'
check "name:arg shows the matched argument" eval '[[ $(print -r -- $out | jq -r ".items[0].title") == "node --port=3000" ]]'
check "name:arg case-insensitive" eval '[[ $(filter "NODE:WORKER" | jq -r ".items[0].arg") == "term 5001@$TOK2" ]]'

for q in 'we(ird' '[x]' 'y|' '"; touch /tmp/pwn; "' '$(id)' '*' 'a:b:c'; do
  out=$(filter "$q"); rc=$?
  check "metachar query '$q' → valid JSON" eval '[[ $rc == 0 ]] && print -r -- $out | jq -e . >/dev/null'
done
check "'(' and '[' match literally" eval '[[ $(titles "we(ird) [x]") == "we(ird) [x]|y" ]]'
check "'|' is literal, not alternation" eval '[[ $(titles "y|chrome") != *Chrome* ]]'
check "no match → info item" eval '[[ $(titles zzzqqq) == "No process matches “zzzqqq”" ]]'
check "empty query → hint item first" eval '[[ $(titles | head -1) == "Kill a process" ]]'
check "processes are sorted by CPU for an empty query" eval '[[ $(titles | sed -n 2p) == "Google Chrome" ]]'

# ==== TASK2 ====

print "\n$pass passed, $fail failed"
(( fail == 0 ))
