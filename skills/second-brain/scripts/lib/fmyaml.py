"""Minimal symmetric YAML frontmatter reader/writer (stdlib only).

Supports the subset used by the brain vaults:
  key: value            (str | quoted str | null | empty)
  key: [a, b, c]        (flow list)
  key:                  (block list)
    - item
Values kept as str, None, or list[str]. Order preserved (dict insertion order).
"""

import re

_KEY_RE = re.compile(r"^([A-Za-z_][\w\-]*)\s*:\s*(.*)$")
_ITEM_RE = re.compile(r"^\s+-\s*(.*)$")


def _unquote(v):
    """Strip YAML quotes. Double-quoted values undo the two escapes `dump`
    writes (\\ and \"); single-quoted values undo ''."""
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] == '"':
        return re.sub(r'\\(["\\])', r"\1", v[1:-1])
    if len(v) >= 2 and v[0] == v[-1] == "'":
        return v[1:-1].replace("''", "'")
    return v


def _parse_scalar(v):
    v = v.strip()
    if v == "" :
        return None
    if v in ("null", "~", "Null", "NULL"):
        return None
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        if not inner:
            return []
        return [_unquote(x) for x in _split_flow(inner)]
    return _unquote(v)


def _split_flow(inner):
    # split on commas not inside quotes or [[ ]]
    parts, buf, depth, quote = [], "", 0, None
    escaped = False
    for ch in inner:
        if quote:
            buf += ch
            if escaped:
                escaped = False
            elif ch == "\\" and quote == '"':
                escaped = True
            elif ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            buf += ch
        elif ch == "[":
            depth += 1
            buf += ch
        elif ch == "]":
            depth -= 1
            buf += ch
        elif ch == "," and depth == 0:
            parts.append(buf)
            buf = ""
        else:
            buf += ch
    if buf.strip():
        parts.append(buf)
    return [p.strip() for p in parts]


def parse(text):
    """Return (fm: dict, body: str). fm == {} when no frontmatter."""
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    raw = text[3:end]
    body = text[end + 4:]
    if body.startswith("\n"):
        body = body[1:]
    fm = {}
    cur = None
    for line in raw.splitlines():
        if not line.strip() or line.strip().startswith("#"):
            continue
        m = _ITEM_RE.match(line) if line[:1] in (" ", "\t", "-") else None
        if m is not None and cur is not None and isinstance(fm.get(cur), (list, type(None))):
            if fm.get(cur) is None:
                fm[cur] = []
            fm[cur].append(_unquote(m.group(1)))
            continue
        k = _KEY_RE.match(line)
        if k:
            cur = k.group(1)
            fm[cur] = _parse_scalar(k.group(2))
    return fm, body


def _needs_quote(v):
    if v == "":
        return True
    return bool(re.search(r"[:#\[\]{}\"']|^[\s\-@&*!|>%]|\s$|^\s", v)) or v in (
        "null", "true", "false", "yes", "no", "~")


def _dump_scalar(v):
    if v is None:
        return "null"
    v = str(v)
    if _needs_quote(v):
        # Escape the backslash first so `_unquote` can reverse both exactly.
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return v


def dump(fm):
    """Serialize fm dict (ordered) to frontmatter block including --- fences."""
    lines = ["---"]
    for k, v in fm.items():
        if isinstance(v, list):
            if not v:
                lines.append(f"{k}: []")
            else:
                lines.append(f"{k}:")
                for item in v:
                    lines.append(f"  - {_dump_scalar(item)}")
        else:
            lines.append(f"{k}: {_dump_scalar(v)}")
    lines.append("---")
    return "\n".join(lines) + "\n"


# Canonical leading key order, shared by every writer (capture, lint
# --fix-safe) so two notes of the same type always serialise identically.
_HEAD = ["type", "schema", "created", "tags"]


def order_fm(fm):
    out = {k: fm[k] for k in _HEAD if k in fm}
    for k, v in fm.items():
        if k not in out:
            out[k] = v
    return out


def compose(fm, body):
    fm = order_fm(fm)
    b = body if body.startswith("\n") else "\n" + body
    if not b.endswith("\n"):
        b += "\n"
    return dump(fm) + b
