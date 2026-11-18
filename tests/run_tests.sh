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

# --- action ----------------------------------------------------------------------
act() { $WF/action.sh "$1" }
klog() { cat $MOCK_DIR/kill.log 2>/dev/null }
alive_in_fixture() { grep -q "^$1	" $MOCK_DIR/procs && [[ ! -e $MOCK_DIR/dead_$1 ]] }

fixtures
msg=$(act "term 5000@$TOK2")
check "term: quits a process that exits on SIGTERM" eval '[[ $msg == "Quit node (PID 5000)" ]]'
check "term: no SIGKILL when SIGTERM was enough" eval '[[ $(klog) == "TERM 5000" ]]'

fixtures; touch $MOCK_DIR/stubborn_5000
msg=$(act "term 5000@$TOK2")
check "term: stubborn process gets SIGKILL after the wait" eval '[[ $(klog) == $'"'"'TERM 5000\nKILL 5000'"'"' && $msg == "Force-killed node (PID 5000): it did not quit in time" ]]'

fixtures
msg=$(act "force 5001@$TOK2")
check "force: SIGKILL right away" eval '[[ $(klog) == "KILL 5001" && $msg == "Force-killed node (PID 5001)" ]]'

fixtures
msg=$(act "term 5000@${T1// /_}")
check "PID reused (start time differs) → refused, nothing signalled" \
  eval '[[ $msg == "PID 5000 is now a different process: nothing was killed" && -z $(klog) ]]'
msg=$(act "term 7777@$TOK2")
check "process already gone → reported, nothing signalled" eval '[[ $msg == "PID 7777 has already exited" && -z $(klog) ]]'
msg=$(act "term 300@${T1// /_}")
check "root process → refused" eval '[[ $msg == "syslogd (PID 300) is owned by root: not killed" && -z $(klog) ]]'
for bad_arg in "term 1@${T1// /_}" "term abc" "term 5000" "rm -rf /" "term -1@x" "term 5000@x;id" "force 0@$TOK2" ""; do
  rm -f $MOCK_DIR/kill.log
  act "$bad_arg" >/dev/null
  [[ -z $(klog) ]] || bad "malformed or protected arg '$bad_arg' signalled something"
done
ok "malformed / protected args never signal"

fixtures; touch $MOCK_DIR/stubborn_4201
msg=$(act "all 4200@$TOK2")
check "all: every process with that path is quit" eval '! alive_in_fixture 4200 && ! alive_in_fixture 4201'
check "all: stubborn one force-killed, others only TERM" \
  eval '[[ $(klog | sort | tr "\n" "|") == "KILL 4201|TERM 4200|TERM 4201|" ]]'
check "all: main Chrome process untouched" eval 'alive_in_fixture 4100'
check "all: summary message" eval '[[ $msg == "Quit 2 × Google Chrome Helper (1 force-killed)" ]]'
fixtures
msg=$(act "all 4200@${T1// /_}")
check "all: stale token refused" eval '[[ $msg == "PID 4200 is now a different process: nothing was killed" && -z $(klog) ]]'

# --- updates ---------------------------------------------------------------------
fixtures
wait_for() { integer i; for (( i = 0; i < 60; i++ )); do eval "$1" && return 0; sleep 0.1; done; return 1 }
UPD=$alfred_workflow_cache/update
zsh $ROOT/scripts/build.sh 9.0.0 >/dev/null
mkdir -p $MOCK_DIR/releases/v9.0.0
mv -f $ROOT/dist/Alfred-Kill-9.0.0.alfredworkflow $ROOT/dist/Alfred-Kill-9.0.0.alfredworkflow.sha256 $MOCK_DIR/releases/v9.0.0/
print 9.0.0 > $MOCK_DIR/latest
update_mode=notify filter >/dev/null
check "empty query starts a background update check" wait_for '[[ $(cat $UPD 2>/dev/null) == "9.0.0 "* ]]'
check "update announced on empty query" eval '[[ $(update_mode=notify titles) == *"Update available: Alfred Kill 9.0.0"* ]]'
check "update item routes to action.sh" eval '[[ $(update_mode=notify filter | jq -r ".items[-1].arg") == "update_install 9.0.0" ]]'
check "no update item while searching" eval '[[ $(update_mode=notify titles chrome) != *"Update available"* ]]'
rm -f $MOCK_DIR/open.log
check "verified update opens in Alfred" \
  eval '[[ $(act "update_install 9.0.0") == "Opening Alfred Kill 9.0.0. Confirm the update in Alfred" && $(<$MOCK_DIR/open.log) == $alfred_workflow_cache/Alfred-Kill-9.0.0.alfredworkflow ]]'
print "0000000000000000000000000000000000000000000000000000000000000000  x" > $MOCK_DIR/releases/v9.0.0/Alfred-Kill-9.0.0.alfredworkflow.sha256
rm -f $MOCK_DIR/open.log
check "tampered update rejected" eval '[[ $(act "update_install 9.0.0") == "Update not installed: checksum mismatch" && ! -e $MOCK_DIR/open.log ]]'
check "update curl calls ignore ~/.curlrc" eval '[[ $(head -1 $MOCK_DIR/curl.log) == -q ]]'

print "\n$pass passed, $fail failed"
(( fail == 0 ))
