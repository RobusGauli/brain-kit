"""Pure text helpers for note bodies (no I/O, no vault knowledge).

Edits are surgical: they touch only the line or section they own and leave the
rest of the body byte-for-byte as it was.
"""

import re

from .core import META_LINES, meta_value

HEADING_RE = re.compile(r"^#{1,6} ")  # a heading, not an Obsidian #tag


def is_heading(line):
    return bool(HEADING_RE.match(line))


def header_end(lines):
    """Index of the first `## ` section heading (or len). Meta lines
    (`**Label:** value`) live above it; below it is prose."""
    return next((i for i, l in enumerate(lines) if l.startswith("## ")), len(lines))


def set_h1(body, fn):
    """Rewrite the H1 text with fn(old) -> new."""
    return re.sub(r"(?m)^# (.+)$", lambda m: "# " + fn(m.group(1)), body, count=1)


def meta_line(label, body):
    """The value of `**Label:** value` in the note header, or None."""
    lines = body.split("\n")
    pat = re.compile(r"^\*\*" + re.escape(label) + r":\*\* ?(.*)$")
    for l in lines[:header_end(lines)]:
        m = pat.match(l)
        if m:
            return m.group(1).strip()
    return None


def rewrite_meta(body, pairs):
    """Make each header `**Label:** value` line say `value` (None removes the
    line). A missing line is added after the last meta line, or under the H1.
    Lines below the first `## ` heading are prose and never touched."""
    lines = body.split("\n")
    for label, value in pairs:
        end = header_end(lines)
        pat = re.compile(r"^\*\*" + re.escape(label) + r":\*\* ?.*$")
        idx = next((i for i in range(end) if pat.match(lines[i])), None)
        text = None if value is None else f"**{label}:** {value}"
        if idx is not None:
            if text is None:
                del lines[idx]
                if 0 < idx < len(lines) and not lines[idx - 1].strip() \
                        and not lines[idx].strip():
                    del lines[idx]  # don't leave a double blank behind
            else:
                lines[idx] = text
        elif text is not None:
            last = max((i for i in range(end)
                        if re.match(r"^\*\*[^*]+:\*\* ?", lines[i])), default=None)
            if last is None:
                at = 1 if lines and lines[0].startswith("# ") else 0
                lines[at:at] = ["", text]
            else:
                lines.insert(last + 1, text)
    return "\n".join(lines)


def sync_meta(ntype, fm, body, fields=None):
    """Re-render the mirrored body lines of `ntype` from its frontmatter."""
    pairs = [(label, meta_value(ntype, field, fm))
             for field, label in META_LINES.get(ntype, {}).items()
             if fields is None or field in fields]
    return rewrite_meta(body, pairs)


def drifted_fields(ntype, fm, body):
    """Fields whose header meta line disagrees with the frontmatter."""
    out = set()
    for field, label in META_LINES.get(ntype, {}).items():
        have = meta_line(label, body)
        if have is not None and have != (meta_value(ntype, field, fm) or ""):
            out.add(field)
    return out


def section_bounds(lines, section):
    """(start, end) line indexes of `## section`, or None."""
    heading = f"## {section}"
    start = next((i for i, l in enumerate(lines) if l.strip() == heading), None)
    if start is None:
        return None
    end = next((j for j in range(start + 1, len(lines)) if is_heading(lines[j])),
               len(lines))
    return start, end


def append_block(body, section, block):
    """Add a prose block at the end of `## section` (created if missing).
    A block already present in that section is not added twice."""
    block = block.strip()
    lines = body.rstrip("\n").split("\n")
    bounds = section_bounds(lines, section)
    if bounds is None:
        return "\n".join(lines + ["", f"## {section}", "", block]) + "\n"
    start, end = bounds
    section_text = re.sub(r"\n{2,}", "\n\n", "\n".join(lines[start + 1:end]).strip())
    if f"\n\n{block}\n\n" in f"\n\n{section_text}\n\n":
        return body  # the whole paragraph is already there
    last = max((j for j in range(start + 1, end) if lines[j].strip()), default=start)
    lines[last + 1:last + 1] = ["", *block.split("\n")]
    return "\n".join(lines) + "\n"


def one_line(text):
    return " ".join((text or "").split())
