# Alfred Kill

Find a running process by name and quit it, safely.

| Type | Does |
|---|---|
| `kill chrome` | fuzzy-match processes: CPU, memory, PID, path, app icon |
| `kill node:server.js` | only processes whose command line contains `server.js` |
| ↩ | quit: `SIGTERM`, then `SIGKILL` if still running after 2 s |
| ⌥↩ | force kill now (`SIGKILL`) |
| ⌘↩ | quit every process of yours running the same program |

## Safety

- **Never the wrong process.** Each result carries the PID *and* its start
  time. Before signalling, the action re-reads the start time and refuses if
  the PID now belongs to a different process (PIDs get reused). It checks again
  before escalating to `SIGKILL`.
- **Your processes only.** Root and other users' processes are listed but not
  actionable; there is no `sudo`. PID 0/1 and the workflow itself are never
  offered.
- **No code from your query.** The query is only compared literally inside
  zsh; it never reaches `eval`, a shell string, `grep` or `ps`. Action
  arguments must be exactly `<verb> <pid>@<start>`.
- Pure zsh + `/bin/ps` + `/bin/kill`. No Ruby, Python or Homebrew.
- Updates come from this repo's GitHub Releases over HTTPS (ignoring
  `~/.curlrc`) and are checked against the release's SHA-256, bundle id and
  version before Alfred is asked to install.

## Development

```sh
zsh tests/run_tests.sh       # mocked test-suite (zsh + jq); never signals a real process
zsh tests/build_test.sh      # packaging test
zsh scripts/build.sh         # dist/Alfred-Kill-<version>.alfredworkflow
python3 scripts/make_plist.py && swift scripts/make_icons.swift   # regenerate
```
