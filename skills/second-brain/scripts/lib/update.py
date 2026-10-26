"""brain update: check for and install a newer brain-kit release.

The only part of the CLI that uses the network, and only when the user runs
`brain update`. It reads the latest release tag from where GitHub's
/releases/latest redirects, then re-runs the official installer for that tag
(install.sh, or install.ps1 on Windows), which swaps the code in place.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

REPO = "RobusGauli/brain-kit"
TAG_RE = re.compile(r"/releases/tag/([A-Za-z0-9._-]+)$")
SKILL_DIR = Path(__file__).resolve().parent.parent.parent  # .../second-brain


def _fetch(url, head=False):
    """(final URL, body) via urllib; falls back to curl, which has its own
    certificates (python.org builds on macOS often have none set up)."""
    try:
        req = urllib.request.Request(url, method="HEAD" if head else "GET",
                                     headers={"User-Agent": "brain-kit"})
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.geturl(), (b"" if head else r.read()).decode("utf-8")
    except Exception:
        if not shutil.which("curl"):
            raise
        if head:
            out = subprocess.run(["curl", "-fsSLI", "-o", os.devnull, "-w",
                                  "%{url_effective}", url],
                                 capture_output=True, text=True, timeout=30)
            if out.returncode:
                raise OSError(f"curl exit {out.returncode}")
            return out.stdout.strip(), ""
        out = subprocess.run(["curl", "-fsSL", url], capture_output=True,
                             timeout=60)
        if out.returncode:
            raise OSError(f"curl exit {out.returncode}")
        return url, out.stdout.decode("utf-8")


def latest_tag():
    final, _ = _fetch(f"https://github.com/{REPO}/releases/latest", head=True)
    m = TAG_RE.search(final)
    if not m:
        raise OSError(f"unexpected answer from GitHub: {final}")
    return m.group(1)


def _vtuple(v):
    nums = re.findall(r"\d+", v)
    return tuple(int(n) for n in nums[:3]) if nums else None


def receipt():
    """The installer's receipt, if this copy was installed by install.sh or
    install.ps1 (it lives at <data>/brain-kit/skills/second-brain)."""
    data = SKILL_DIR.parent.parent
    if SKILL_DIR.parent.name != "skills" or data.name != "brain-kit":
        return None, data
    try:
        return json.loads((data / "install.json").read_text(encoding="utf-8")), data
    except (OSError, ValueError):
        return None, data


def run(version, check=False, to=None):
    rec, data = receipt()
    how = (f"{rec.get('method')}, {rec.get('source')}, "
           f"{str(rec.get('installed_at', ''))[:10]}") if rec else f"{SKILL_DIR}"
    print(f"installed: {version} ({how})")

    if to:
        if not re.fullmatch(r"[A-Za-z0-9._-]+", to):
            print(f"ERROR: --to {to!r} is not a tag name.", file=sys.stderr)
            return 2
        target = to
    else:
        try:
            target = latest_tag()
        except Exception as exc:  # network, DNS, proxy, GitHub down
            print(f"ERROR: could not reach GitHub to find the latest release "
                  f"({exc}). Nothing was changed.", file=sys.stderr)
            return 1
        print(f"latest:    {target}")
        newer = (_vtuple(target) or (0,)) > (_vtuple(version) or (0,))
        if not newer:
            print("up to date.")
            return 0
        if check:
            print(f"update available: {version} -> {target}. Run `brain update`.")
            return 0
    if check:
        return 0

    if rec is None:
        print("This copy was not installed by the brain-kit installer, so "
              "`brain update` will not replace it. Update it with the tool "
              "you used: `npx skills update`, `gh skill update`, or "
              "`git pull` in your clone. Nothing was changed.")
        return 1

    print(f"updating to {target} ...", flush=True)
    rpath = data / "install.json"
    before = rpath.read_text(encoding="utf-8") if rpath.exists() else None
    code = _install(target, data)
    if code == 0 and (not rpath.exists()
                      or rpath.read_text(encoding="utf-8") == before):
        _rewrite_receipt(rpath, target, data)  # releases before 1.0.1 write none
    return code


def _rewrite_receipt(rpath, target, data):
    import datetime
    out = subprocess.run([sys.executable, "-B", str(SKILL_DIR / "scripts" / "brain"),
                          "--version"], capture_output=True, text=True)
    version = out.stdout.strip().replace("second-brain ", "") or target.lstrip("v")
    rec = {"version": version, "source": f"{REPO}@{target}", "method": "brain update",
           "installed_at": datetime.datetime.now(datetime.timezone.utc)
                           .strftime("%Y-%m-%dT%H:%M:%SZ")}
    with open(rpath, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(rec, indent=2) + "\n")


def _install(target, data):
    """Run the official installer for `target`, keeping the install folder."""
    env = dict(os.environ, BRAIN_KIT_REF=target)
    base = f"https://raw.githubusercontent.com/{REPO}/{target}"
    try:
        if os.name == "nt":
            env["LOCALAPPDATA"] = str(data.parent)  # keep the same install folder
            cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                   "-Command", f"irm {base}/install.ps1 | iex"]
            proc = subprocess.run(cmd, env=env)
        else:
            env["XDG_DATA_HOME"] = str(data.parent)  # keep the same install folder
            _, script = _fetch(f"{base}/install.sh")
            proc = subprocess.run(["sh", "-s"], input=script.encode("utf-8"),
                                  env=env)
    except Exception as exc:
        print(f"ERROR: could not run the installer for {target} ({exc}). "
              "Nothing was changed.", file=sys.stderr)
        return 1
    return proc.returncode
