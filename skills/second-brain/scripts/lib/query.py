"""brain query * — complete one-shot markdown answers."""

import re
from pathlib import Path

from . import fmyaml
from .core import iso_week, owner_link, parse_date, self_words, slugify, today
from .linter import vault_files
from .people import people_stems, resolve_stem
from .writer import section_text


def _notes(vault, folder=None, ntype=None):
    out = []
    for rel in vault_files(vault):
        if folder and not rel.startswith(folder + "/"):
            continue
        fm, body = fmyaml.parse((vault / rel).read_text(encoding="utf-8"))
        if ntype and fm.get("type") != ntype:
            continue
        out.append((rel, fm, body))
    return out


def _title(rel, body):
    m = re.search(r"^# (.+)$", body, re.MULTILINE)
    return m.group(1).strip() if m else Path(rel).stem


def _task_line(rel, fm, body):
    slug = Path(rel).stem
    bits = [f"priority: {fm.get('priority')}", f"area: {fm.get('area')}"]
    if fm.get("project"):
        bits.append(f"project: {fm['project']}")
    if fm.get("week"):
        bits.append(f"week: {fm['week']}")
    if fm.get("owner") not in (None, "", owner_link()):
        bits.append(f"owner: {fm['owner']}")
    return f"- [[Tasks/{slug}]] — {_title(rel, body)} ({', '.join(bits)})"


def _owner_name(fm):
    o = str(fm.get("owner") or owner_link() or "")
    return o.strip("[]").split("/")[-1].split("|")[0]


def mine(fm):
    """The owner's own tasks. `owner` is required; a hand-written task with no
    owner counts as theirs."""
    return fm.get("owner") in (None, "", owner_link())


def _owner_filter(tasks, owner):
    """--owner me|all|<name>. Default 'me' keeps other people's action items out
    of the backlog."""
    o = (owner or "me").strip().lower()
    if o == "all":
        return tasks
    if o in self_words():
        return [t for t in tasks if mine(t[1])]
    return [t for t in tasks if o in _owner_name(t[1]).lower().replace("-", " ")]


def _mentions_project(rel, body, tokens):
    hay = (Path(rel).stem + " " + _title(rel, body)).lower()
    return all(t in hay for t in tokens)


def cmd_tasks(vault, args):
    owner = getattr(args, "owner", "me")
    all_tasks = _owner_filter(_notes(vault, "Tasks", "task"), owner)
    tasks = all_tasks
    if args.status:
        tasks = [t for t in tasks if t[1].get("status") == args.status]
    scoped = tasks
    if args.project:
        scoped = [t for t in tasks if t[1].get("project") == args.project]
    who = "mine" if (owner or "me").lower() in self_words() else owner
    print(f"# Tasks ({len(scoped)}; owner: {who})")
    for status in ("this-week", "backlog", "done"):
        grp = [t for t in scoped if t[1].get("status") == status]
        if not grp:
            continue
        print(f"\n## {status} ({len(grp)})")
        for rel, fm, body in grp:
            print(_task_line(rel, fm, body))
    if args.project:
        # A task can name the project in its title while being filed under a
        # parent/umbrella project. The one-shot answer must surface those too:
        # query output is the complete answer, with no follow-up reads.
        toks = [t for t in args.project.split("-") if len(t) > 2]
        related = [t for t in tasks
                   if t[1].get("project") != args.project
                   and _mentions_project(t[0], t[2], toks)]
        print(f"\n## also mentioning '{args.project}' (filed under another project) "
              f"({len(related)})")
        for rel, fm, body in related:
            print(f"- [{fm.get('status')}] " + _task_line(rel, fm, body)[2:])


def cmd_working_on(vault, args):
    print("# Working on")
    projects = [(r, f, b) for r, f, b in _notes(vault, "Projects", "project")
                if f.get("status") == "active"]
    print(f"\n## Active projects ({len(projects)})")
    for rel, fm, body in projects:
        print(f"- [[{rel[:-3]}]] — {_title(rel, body)} (area: {fm.get('area')})")
    tasks = [(r, f, b) for r, f, b in _notes(vault, "Tasks", "task")
             if f.get("status") == "this-week" and mine(f)]
    print(f"\n## This-week tasks ({len(tasks)})")
    for rel, fm, body in tasks:
        print(_task_line(rel, fm, body))


def cmd_waiting_on(vault, args):
    fus = [(r, f, b) for r, f, b in _notes(vault, "Follow-ups", "followup")
           if f.get("status") == "waiting"]
    print(f"# Waiting on\n\n## Open follow-ups ({len(fus)})")
    for rel, fm, body in fus:
        print(f"- [[Follow-ups/{Path(rel).stem}]] — {fm.get('who')} re: "
              f"{fm.get('about')} (opened {fm.get('opened')})")
    # Action items OTHER people owe — captured as tasks with owner != the vault owner so
    # they never pollute the backlog, but they are still things the owner is waiting
    # on and belong in the one-shot answer.
    owed = [(r, f, b) for r, f, b in _notes(vault, "Tasks", "task")
            if not mine(f) and f.get("status") != "done"]
    print(f"\n## Action items owed by others ({len(owed)})")
    for rel, fm, body in owed:
        print(f"- {_owner_name(fm)}: [[Tasks/{Path(rel).stem}]] — "
              f"{_title(rel, body)} (source: {fm.get('source') or '—'})")
    if not owed:
        print("- (none)")
    print("\n## Waiting On lines in recent daily notes")
    dailies = sorted(_notes(vault, "Daily", "daily"), reverse=True)[:14]
    any_line = False
    for rel, fm, body in dailies:
        sec = section_text(body, "Waiting On")
        lines = [l for l in sec.splitlines()
                 if l.strip().startswith("-") and l.strip() not in ("-", "- [ ]")]
        for l in lines:
            print(f"- {Path(rel).stem}: {l.strip().lstrip('- ').strip()}")
            any_line = True
    if not any_line:
        print("- (none)")


def cmd_today(vault, args):
    d = today().isoformat()
    rel = f"Daily/{d}.md"
    print(f"# Today — {d} ({iso_week()})")
    p = vault / rel
    if p.exists():
        _, body = fmyaml.parse(p.read_text(encoding="utf-8"))
        print(f"\n## Daily note ({rel})\n")
        print(body.strip())
    else:
        print(f"\n## Daily note\n\n(none yet — {rel} does not exist)")
    tasks = [(r, f, b) for r, f, b in _notes(vault, "Tasks", "task")
             if f.get("status") == "this-week" and mine(f)]
    print(f"\n## This-week tasks ({len(tasks)})")
    for r, f, b in tasks:
        print(_task_line(r, f, b))


def cmd_person(vault, args):
    name = args.name
    stem = resolve_stem(name, people_stems(vault))
    rel = f"People/{stem}.md" if stem else None
    if rel is None:
        print(f"# {name}\n\nNo People note found for '{name}'.")
        return
    fm, body = fmyaml.parse((vault / rel).read_text(encoding="utf-8"))
    stem = Path(rel).stem
    print(f"# {_title(rel, body)} ([[{rel[:-3]}]])\n")
    show = lambda k: fm.get(k) or "—"
    print(f"- org: {show('org')}  role: {show('role')}  email: {show('email')}")
    print(f"\n## Note body\n\n{body.strip()}")
    print("\n## Mentions")
    pat = re.compile(r"\[\[People/" + re.escape(stem) + r"(\]\]|\|)")
    hits = []
    for r in vault_files(vault):
        if r == rel:
            continue
        text = (vault / r).read_text(encoding="utf-8")
        if pat.search(text):
            hits.append(r)
    for h in hits:
        print(f"- [[{h[:-3]}]]")
    if not hits:
        print("- (none)")


def _project_notes(vault):
    return _notes(vault, "Projects", "project")


def cmd_project(vault, args):
    """One-shot project status: note fm + body + its tasks + recent meetings."""
    want = slugify(args.name)
    projects = _project_notes(vault)
    exact = [(r, f, b) for r, f, b in projects if Path(r).stem == want]
    matches = exact or [(r, f, b) for r, f, b in projects
                        if want in Path(r).stem or Path(r).stem in want]
    if not matches:
        print(f"# Project '{args.name}'\n\nNo project note matches '{want}'.")
        print("\n## All projects")
        for r, f, b in projects:
            print(f"- [[{r[:-3]}]] ({f.get('status')})")
        return
    if len(matches) > 1:
        print(f"# Project '{args.name}' — {len(matches)} matches\n")
        for r, f, b in matches:
            print(f"- [[{r[:-3]}]] — {_title(r, b)} (status: {f.get('status')}, "
                  f"area: {f.get('area')})")
        return
    rel, fm, body = matches[0]
    slug = Path(rel).stem
    print(f"# {_title(rel, body)} ([[{rel[:-3]}]])\n")
    print(f"- status: {fm.get('status')}  area: {fm.get('area')}")
    print(f"\n## Note body\n\n{body.strip()}")
    tasks = [(r, f, b) for r, f, b in _notes(vault, "Tasks", "task")
             if f.get("project") == slug and f.get("status") != "done"]
    print(f"\n## Open tasks ({len(tasks)})")
    for r, f, b in tasks:
        print(f"- [{f.get('status')}] " + _task_line(r, f, b)[2:])
    meetings = [(r, f, b) for r, f, b in _notes(vault, "Meetings", "meeting")
                if f.get("project") == slug]
    meetings.sort(key=lambda m: (str(m[1].get("date", "")), m[0]), reverse=True)
    print(f"\n## Meetings ({len(meetings)}, newest first)")
    for r, f, b in meetings[:10]:
        print(f"- {f.get('date')} [[{r[:-3]}]] — {_title(r, b)}")


def cmd_meetings(vault, args):
    meetings = _notes(vault, "Meetings", "meeting")
    if args.since:
        args.since = parse_date(args.since, "--since")
        meetings = [m for m in meetings if str(m[1].get("date", "")) >= args.since]
    meetings.sort(key=lambda m: (str(m[1].get("date", "")), m[0]), reverse=True)
    print(f"# Meetings ({len(meetings)})")
    for rel, fm, body in meetings:
        att = ", ".join(fm.get("attendees") or [])
        proj = fm.get("project") or "—"
        print(f"- {fm.get('date')} [[{rel[:-3]}]] — {_title(rel, body)} "
              f"(project: {proj}; attendees: {att or '—'})")
