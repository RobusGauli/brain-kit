"""Resolve a reference taken from query output to one existing note.

A ref is what every query line already prints: `Folder/stem` (or just the
stem, or `[[Folder/stem]]`). Resolution is deterministic and never guesses
across notes, except for people and projects, which follow the same rules as
`query person` and `query project`.
"""

from pathlib import Path

from .core import FOLDER_BY_TYPE, die, parse_date, slug_key, slugify
from .people import AmbiguousPerson, people_stems, resolve_stem
from .projects import project_rels


def clean_ref(ref):
    r = (ref or "").strip()
    if r.startswith("[[") and r.endswith("]]"):
        r = r[2:-2].split("|")[0].split("#")[0]
    r = r.strip().strip("/")
    return r[:-3] if r.endswith(".md") else r


def _stem_of(ref, folder, ntype):
    if "/" in ref:
        head, _, tail = ref.partition("/")
        if head != folder:
            die(f"'{ref}' is not a {ntype} note (expected {folder}/<name>). "
                "Nothing was written.")
        ref = tail
    return ref


def resolve_ref(vault, ntype, ref):
    """Return the vault-relative path of the one note `ref` names, or exit 2."""
    folder = FOLDER_BY_TYPE[ntype]
    raw = clean_ref(ref)
    stem = _stem_of(raw, folder, ntype)
    if not stem:
        die(f"empty {ntype} reference. Nothing was written.")

    if ntype == "daily":
        return f"Daily/{parse_date(stem, f'{ntype} date')}.md"

    if ntype == "person":
        try:
            found = resolve_stem(stem, people_stems(vault), strict=True)
        except AmbiguousPerson as exc:
            cands = ", ".join(f"People/{c}" for c in exc.candidates)
            die(f"'{exc.name}' matches {len(exc.candidates)} people: {cands}. "
                "Use the full name. Nothing was written.")
        if not found:
            die(f"no such person: '{stem}'. Nothing was written.")
        return f"People/{found}.md"

    if ntype == "project":
        projects = project_rels(vault)
        # exact slug, either spelling (`capture project` builds its slug with
        # slug_key, which drops stopwords), else a unique partial name
        for cand in (slugify(stem), slug_key(stem, 5)):
            if cand in projects:
                return projects[cand]
        want = slugify(stem)
        words = want.split("-") if want else []
        hits = sorted(s for s in projects
                      if words and all(w in s.split("-") for w in words))
        if len(hits) == 1:
            return projects[hits[0]]
        if hits:
            die(f"'{stem}' matches {len(hits)} projects: "
                + ", ".join(f"Projects/{s}" for s in hits)
                + ". Use one of those. Nothing was written.")
        die(f"no such project: '{stem}'. Create it with `brain capture project`. "
            "Nothing was written.")

    rel = f"{folder}/{stem}.md"
    if not (Path(vault) / rel).is_file():
        die(f"no such {ntype}: {rel}. Nothing was written.")
    return rel
