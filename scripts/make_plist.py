#!/usr/bin/env python3
"""Regenerate workflow/info.plist (dev-only, stdlib only).

Object graph:
  Script Filter filter.sh ──↩ / ⌥↩ / ⌘↩──▶ Run Script action.sh ──▶ Notification
(each item carries its own verb in the arg, so every modifier goes to action.sh)
"""
import plistlib
from pathlib import Path

VERSION = "1.0.0"
CMD, ALT = 1048576, 524288
U = lambda n: f"4B1D0000-{n:04d}-4000-8000-{n:012d}"
SF, RUN, NOTE = (U(i) for i in range(1, 4))

README = """Alfred Kill — find a process by name and quit it safely.

  kill <name>          fuzzy-match running processes (CPU, memory, PID, path)
  kill <name>:<arg>    only processes whose command line contains <arg>

  ↩    quit: SIGTERM, then SIGKILL if it hasn't exited after 2 seconds
  ⌥↩   force kill now (SIGKILL)
  ⌘↩   quit every process of yours running the same program

Before anything is signalled the PID's start time is re-checked, so a PID
that was reused by another process since the list was drawn is never killed.
Processes owned by root or other users are shown but never killed (no sudo).

Source & docs: https://github.com/nadavshatz/alfred-kill"""

objects = [
    {"type": "alfred.workflow.input.scriptfilter", "uid": SF, "version": 3, "config": {
        "alfredfiltersresults": False, "alfredfiltersresultsmatchmode": 0,
        "argumenttreatemptyqueryasnil": True, "argumenttrimmode": 0, "argumenttype": 1,
        "escaping": 102, "keyword": "{var:keyword}", "queuedelaycustom": 3,
        "queuedelayimmediatelyinitially": True, "queuedelaymode": 0, "queuemode": 1,
        "runningsubtext": "Reading processes…", "script": "", "scriptargtype": 1,
        "scriptfile": "filter.sh", "subtext": "Find a process and quit it",
        "title": "Kill a process", "type": 8, "withspace": True}},
    {"type": "alfred.workflow.action.script", "uid": RUN, "version": 2, "config": {
        "concurrently": False, "escaping": 102, "script": "", "scriptargtype": 1,
        "scriptfile": "action.sh", "type": 8}},
    {"type": "alfred.workflow.output.notification", "uid": NOTE, "version": 1, "config": {
        "lastpathcomponent": False, "onlyshowifquerypopulated": True,
        "removeextension": False, "text": "{query}", "title": "Alfred Kill"}},
]


def link(dst, mods=0, sub=""):
    return {"destinationuid": dst, "modifiers": mods, "modifiersubtext": sub, "vitoclose": False}


connections = {
    SF: [link(RUN), link(RUN, ALT, ""), link(RUN, CMD, "")],
    RUN: [link(NOTE)],
}

user_config = [
    {"type": "textfield", "variable": "keyword", "label": "Keyword", "description": "",
     "config": {"default": "kill", "placeholder": "kill", "required": True, "trim": True}},
    {"type": "popupbutton", "variable": "update_mode", "label": "Updates",
     "description": "Checks GitHub Releases once a day. Installing always goes through Alfred's own update prompt.",
     "config": {"default": "notify", "pairs": [["Tell me in Alfred", "notify"],
                                              ["Download and open automatically", "auto"],
                                              ["Never check", "off"]]}},
]

pos = {SF: (40, 120), RUN: (300, 120), NOTE: (520, 120)}

plist = {
    "bundleid": "io.github.nadavshatz.kill",
    "category": "Tools",
    "connections": connections,
    "createdby": "Nadav Shatz",
    "description": "Find a process by name and quit it safely",
    "disabled": False,
    "name": "Alfred Kill",
    "objects": objects,
    "readme": README,
    "uidata": {u: {"xpos": x, "ypos": y} for u, (x, y) in pos.items()},
    "userconfigurationconfig": user_config,
    "version": VERSION,
    "webaddress": "https://github.com/nadavshatz/alfred-kill",
}

out = Path(__file__).resolve().parent.parent / "workflow" / "info.plist"
out.write_bytes(plistlib.dumps(plist, sort_keys=True))
print(f"wrote {out}")
