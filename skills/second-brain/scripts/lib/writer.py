"""Two-phase atomic writer: build notes in memory, lint, then write all.

Every mutation goes through a Plan. Plan.execute():
  1. lints every pending note against (disk index ∪ pending set)
  2. refuses (exit 1, nothing written) on any lint error
  3. writes all files (mkdir -p parents), rolling back on I/O error
  4. prints sorted `WROTE|UPDATED|UNCHANGED <vault>/<rel>` lines, then any
     `MATCHED` notices (a request that landed on an existing note)
"""

import re
import sys
from pathlib import Path

from . import fmyaml
from .core import write_text
from .linter import link_index, lint_note

# scripts/lib/writer.py -> <skill>/assets/templates
TEMPLATES = Path(__file__).resolve().parent.parent.parent / "assets" / "templates"


def prune_empty_sections(body, keep=()):
    """Drop `## Heading` blocks that carry no content: a note must not ship
    five blank headings. Sections in `keep` always stay
    (they are the ones later commands append links into)."""
    lines = body.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("## "):
            name = line[3:].strip()
            j = i + 1
            while j < len(lines) and not re.match(r"^#{1,6} ", lines[j]):
                j += 1
            content = "\n".join(lines[i + 1:j]).strip()
            if not content and name not in keep:
                i = j
                continue
        out.append(line)
        i += 1
    return re.sub(r"\n{3,}", "\n\n", "\n".join(out)).strip("\n") + "\n"


def render(name, mapping, prune=False, keep=()):
    text = (TEMPLATES / f"{name}.md").read_text(encoding="utf-8")
    for k, v in mapping.items():
        text = text.replace("{{" + k + "}}", v or "")
    text = re.sub(r"\{\{[a-z_]+\}\}", "", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    text = text.strip("\n") + "\n"
    if prune:
        text = prune_empty_sections(text, keep)
    return text


def ensure_line_in_section(body, section, line):
    """Idempotently add `line` under `## section` (created at end if missing)."""
    heading = f"## {section}"
    lines = body.split("\n")
    if line in (l.strip() for l in lines):
        return body
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == heading)
    except StopIteration:
        out = body.rstrip("\n") + f"\n\n{heading}\n{line}\n"
        return out
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if re.match(r"^#{1,6} ", lines[j]):
            end = j
            break
    # insert after last non-empty line of the section
    insert_at = start + 1
    for j in range(start + 1, end):
        if lines[j].strip():
            insert_at = j + 1
    lines.insert(insert_at, line)
    return "\n".join(lines)


def section_text(body, section):
    heading = f"## {section}"
    lines = body.split("\n")
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == heading)
    except StopIteration:
        return ""
    out = []
    for l in lines[start + 1:]:
        if re.match(r"^#{1,6} ", l):
            break
        out.append(l)
    return "\n".join(out).strip("\n")


class Plan:
    def __init__(self, ctx, mode):
        self.ctx = ctx
        self.mode = mode
        self.vault = Path(ctx.vault(mode))
        self.pending = {}  # rel -> (fm, body)
        self.linked = set()  # existing notes reused untouched -> LINKED lines
        self.notices = []  # MATCHED lines, printed after the verb lines

    def load(self, rel):
        """Current (fm, body) — pending wins over disk. None if absent."""
        if rel in self.pending:
            return self.pending[rel]
        p = self.vault / rel
        if p.exists():
            return fmyaml.parse(p.read_text(encoding="utf-8"))
        return None

    def put(self, rel, fm, body):
        self.pending[rel] = (fm, body)

    def touch(self, rel):
        """Register an existing note as unchanged so the run still prints an
        `UNCHANGED` line: a write command never exits silently."""
        got = self.load(rel)
        if got is not None:
            self.pending.setdefault(rel, got)

    def _duplicate_task_titles(self):
        """Vault-level rule the per-note lint cannot see: two task notes with
        the same title (disk plus pending)."""
        titles = {}
        d = self.vault / "Tasks"
        rels = {f"Tasks/{f.name}" for f in d.glob("*.md")} if d.is_dir() else set()
        rels |= {r for r in self.pending if r.startswith("Tasks/")}
        errors = []
        for rel in sorted(rels):
            got = self.load(rel)
            if not got or got[0].get("type") != "task":
                continue
            m = re.search(r"^# (.+)$", got[1], re.MULTILINE)
            if not m:
                continue
            key = m.group(1).strip().lower()
            if key in titles:
                # blame a note this run touches; an old duplicate stays a lint matter
                if rel in self.pending or titles[key] in self.pending:
                    errors.append((rel, "title", "duplicate task definition "
                                   f"(same title as {titles[key]})"))
            else:
                titles[key] = rel
        return errors

    def notice(self, rel, text):
        line = f"MATCHED {self.mode}/{rel}: {text}"
        if line not in self.notices:
            self.notices.append(line)

    def _drop_noise_dailies(self):
        """Never create a brand-new daily note that nothing links into: an
        empty Daily/<date>.md is pure vault noise. Existing dailies are
        untouched; a daily we DO create always carries the full template body
        plus at least one real line."""
        for rel in [r for r in self.pending if r.startswith("Daily/")]:
            if (self.vault / rel).exists():
                continue
            _, body = self.pending[rel]
            has_content = any(
                l.strip() and not l.startswith("#") and l.strip() != "---"
                for l in body.split("\n"))
            if not has_content:
                del self.pending[rel]

    def execute(self):
        self._drop_noise_dailies()
        idx = link_index(self.vault, extra=list(self.pending))
        errors = self._duplicate_task_titles()
        for rel in sorted(self.pending):
            fm, body = self.pending[rel]
            errs, _ = lint_note(rel, fm, body, idx)
            errors += errs
        if errors:
            for rel, field, prob in sorted(errors):
                print(f"{self.mode}/{rel}:{field}:{prob}", file=sys.stderr)
            print("REFUSED: lint failed — nothing written.", file=sys.stderr)
            sys.exit(1)

        # snapshot originals for rollback
        originals = {}
        for rel in self.pending:
            p = self.vault / rel
            originals[rel] = p.read_text(encoding="utf-8") if p.exists() else None

        written = []
        try:
            for rel in sorted(self.pending):
                fm, body = self.pending[rel]
                new_text = fmyaml.compose(fm, body)
                p = self.vault / rel
                old = originals[rel]
                if old == new_text:
                    written.append(("UNCHANGED", rel))
                    continue
                p.parent.mkdir(parents=True, exist_ok=True)
                write_text(p, new_text)
                written.append(("WROTE" if old is None else "UPDATED", rel))
        except Exception as exc:  # rollback
            for rel, old in originals.items():
                p = self.vault / rel
                if old is None:
                    if p.exists():
                        p.unlink()
                else:
                    write_text(p, old)
            print(f"REFUSED: write failed ({exc}) — rolled back.", file=sys.stderr)
            sys.exit(1)

        for rel in sorted(self.linked - set(self.pending)):
            written.append(("LINKED", rel))
        for verb, rel in sorted(written, key=lambda x: x[1]):
            print(f"{verb} {self.mode}/{rel}")
        for line in self.notices:
            print(line)
        return written
