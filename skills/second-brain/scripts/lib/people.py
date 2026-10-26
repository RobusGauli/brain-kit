"""Shared, deterministic person-name resolution — used by BOTH the write path
(capture attendees/followups) and the read path (query person).

Rule (in order, first hit wins):
  1. exact stem match: person_filename(name) already exists
  2. unique first-token match: exactly one known stem whose first token equals
     the name's first token, or is a >=3-char prefix of it (Sam <- Samuel),
     or vice versa
  3. no match -> None (caller creates a new Firstname-Lastname note)
"""

from .core import person_filename


def _first_token(s):
    t = s.replace("-", " ").split()
    return t[0].lower() if t else ""


def _tokens(s):
    return [t for t in s.replace("-", " ").split() if t]


class AmbiguousPerson(Exception):
    """A single-token name matches more than one existing People note."""

    def __init__(self, name, candidates):
        self.name = name
        self.candidates = sorted(candidates)
        super().__init__(name)


def resolve_stem(name, stems, strict=False):
    """Resolve a display name to an existing People stem, else None.
    `stems` must be an iterable of existing People note stems.

    Guard: two FULL names (>=2 tokens each) only match on an equal first token
    if their LAST tokens also match — 'Maya Chen' must never resolve to an
    existing 'Maya-Park'. First-token matching stays available for the
    single-token case ('Sam' -> 'Samuel-Ortiz').

    Single-token names never fork the identity graph. Exactly one prefix match
    ALWAYS links that note — 'Sam' can never create a second `People/Sam.md`
    beside an existing `People/Sam-Ortiz.md`. More than one match is
    genuinely ambiguous: with `strict` (the write path) that raises
    `AmbiguousPerson` so the caller can refuse and name the candidates, rather
    than silently minting a third note for the same human."""
    stems = sorted(set(stems))
    first = _first_token(name)
    name_toks = _tokens(name)
    if person_filename(name) in stems:
        return person_filename(name)
    matches = []
    for stem in stems:
        stok = _first_token(stem)
        if not (stok == first or (len(stok) >= 3 and first.startswith(stok))
                or (len(first) >= 3 and stok.startswith(first))):
            continue
        stem_toks = _tokens(stem)
        if len(name_toks) >= 2 and len(stem_toks) >= 2 \
                and name_toks[-1].lower() != stem_toks[-1].lower():
            continue  # different surnames -> different people
        matches.append(stem)
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1 and len(name_toks) == 1 and strict:
        raise AmbiguousPerson(name, matches)
    return None


def people_stems(vault):
    d = vault / "People"
    return sorted(f.stem for f in d.glob("*.md")) if d.is_dir() else []
