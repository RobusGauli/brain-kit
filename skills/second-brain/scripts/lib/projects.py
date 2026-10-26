"""Active-project lookup shared by capture (project inference) and query."""

from pathlib import Path

from . import fmyaml


def active_project_slugs(vault):
    """Stems of Projects/**/*.md notes whose frontmatter is type: project,
    status: active. A nested project folder uses its own note stem."""
    d = vault / "Projects"
    if not d.is_dir():
        return []
    out = []
    for f in sorted(d.rglob("*.md")):
        try:
            fm, _ = fmyaml.parse(f.read_text(encoding="utf-8"))
        except OSError:
            continue
        if fm.get("type") == "project" and fm.get("status") == "active":
            out.append(f.stem)
    return sorted(set(out))
