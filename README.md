# second-brain

An [Agent Skill](https://agentskills.io) that turns a coding agent (Claude Code,
Codex, Cursor, Kiro, ...) into the front end of a personal knowledge system kept
in two [Obsidian](https://obsidian.md) vaults: one for **work**, one for
**personal** life.

You say "log this meeting", "remind me to send the budget", "what am I waiting
on?", and the agent turns that into one command for a small Python CLI. The CLI
writes meetings, interviews, transcripts, tasks, follow-ups, people, projects
and daily notes as plain markdown with consistent frontmatter, and answers
questions about them.

## Why a deterministic CLI behind a thin skill

Letting a model edit markdown files directly works, until it doesn't: two
sessions given the same words write different filenames, forget the daily-note
link, invent a new frontmatter field, create `People/Maya.md` next to an
existing `People/Maya-Chen.md`, or leave a note with five empty headings.

This project splits the job:

- **The skill (`SKILL.md`)** is a short router. Its only job is to map the
  user's words to one CLI command, using fixed rules for every flag so the same
  request produces the same command.
- **The CLI (`scripts/brain`)** does every read and write, deterministically:
  - one command creates the full artifact set (note + tasks + follow-ups +
    people stubs + daily-note links);
  - every write is linted in memory first; if anything fails, nothing is
    written;
  - re-running a command is idempotent (byte-identical vault);
  - filenames, project inference and person matching follow fixed rules, not
    model judgment;
  - queries return one complete markdown answer, so the agent never needs to
    `ls` or `grep` the vault.

The CLI is Python 3 standard library only. No dependencies, and no network,
except `brain update`, which runs only when you ask.

## Install

Requires Python 3.9+ on macOS, Linux or Windows.

**The quick way: ask your agent.** Paste this into Claude Code, Codex or Cursor:

```
set up https://raw.githubusercontent.com/RobusGauli/brain-kit/main/skills/second-brain/SKILL.md
```

The agent reads the skill, runs the installer, asks for your two vault folders
and your name, and runs `init`.

**Or run the installer yourself:**

```sh
curl -fsSL https://raw.githubusercontent.com/RobusGauli/brain-kit/main/install.sh | sh
```

On Windows, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/RobusGauli/brain-kit/main/install.ps1 | iex
```

On Windows the copy goes to `%LOCALAPPDATA%\brain-kit\`, the links are
directory junctions (no admin rights needed), and PATH is not changed. Run the
CLI as `py -3 <path>\scripts\brain`; the installer prints the exact command.

The installer downloads the **latest release** (not the `main` branch) and
copies `skills/second-brain/` to `~/.local/share/brain-kit/`, with a receipt in
`install.json`. It links it into `~/.claude/skills/` and
`~/.agents/skills/`. It also links it into `~/.cursor/skills/` and
`~/.kiro/skills/` when those tools are installed. It links the CLI to
`~/.local/bin/brain`, unless a `brain` command already exists. It never
replaces a file or link it did not create, and it never touches your vaults or
config. You can read [install.sh](install.sh) before you run it. It is short.

To install a specific version, pin it:

```sh
curl -fsSL https://raw.githubusercontent.com/RobusGauli/brain-kit/main/install.sh | sh -s v1.1.0
```

```powershell
$env:BRAIN_KIT_REF = 'v1.1.0'; irm https://raw.githubusercontent.com/RobusGauli/brain-kit/main/install.ps1 | iex
```

### Updating

| You installed with | Update with |
|---|---|
| `install.sh` / `install.ps1` | `brain update` (or ask your agent to "update brain-kit") |
| `npx skills add` | `npx skills update` |
| `gh skill install` | `gh skill update` |
| `git clone` | `git pull` |

`brain update --check` only reports whether a newer release exists.
`brain update --to v1.0.0` installs a specific release, to pin or roll back.
These are the only commands that use the network, and they never run on their
own. See [CHANGELOG.md](CHANGELOG.md) for what changed in each release.

### Manual install

Get the code:

```sh
git clone https://github.com/RobusGauli/brain-kit
```

Then copy or symlink the **skill folder** `skills/second-brain/` (not the repo
root) into a skills directory your agent reads:

| Agent | Project | User (all projects) |
|---|---|---|
| Claude Code | `.claude/skills/` | `~/.claude/skills/` |
| Codex | `.agents/skills/` (in the cwd, a parent, or the repo root) | `~/.agents/skills/` |
| Cursor | `.agents/skills/` or `.cursor/skills/` (also reads `.claude/skills/`) | `~/.agents/skills/` or `~/.cursor/skills/` |
| Kiro | `.kiro/skills/` (workspace) | `~/.kiro/skills/` (global; Kiro IDE only, not Kiro CLI/Web) |

`~/.agents/skills/` covers Codex and Cursor with one copy:

```sh
mkdir -p ~/.agents/skills ~/.claude/skills
ln -s "$PWD/brain-kit/skills/second-brain" ~/.agents/skills/second-brain   # Codex + Cursor
ln -s "$PWD/brain-kit/skills/second-brain" ~/.claude/skills/second-brain   # Claude Code
```

**Kiro** can also import it from GitHub: Agent Steering & Skills → **+** →
Import a skill → paste the URL of the skill **subfolder**
(`https://github.com/RobusGauli/brain-kit/tree/main/skills/second-brain`), not
the repo root.

**Optional, third-party:** Vercel's `skills` CLI can install into several
agents at once:

```sh
npx skills add RobusGauli/brain-kit -a claude-code -a codex -a cursor
```

The skill finds the CLI relative to its own `SKILL.md` and runs it with
`python3`, so it works from any of these locations even if the executable bit
was lost in copying. You can also put `scripts/brain` on your `PATH` for use in a
terminal.

## Configure

Run `init` once:

```sh
# Generic form: B="<skill dir>/scripts/brain"
B="$HOME/.claude/skills/second-brain/scripts/brain"   # Claude Code user install
python3 "$B" init --work-vault ~/Obsidian/Work --personal-vault ~/Obsidian/Personal \
        --owner "Maya Chen" --org-domain example.com
python3 "$B" status
```

`init` writes `${XDG_CONFIG_HOME:-~/.config}/second-brain/config` and creates
any missing vault folders, a vault `README.md`, Obsidian `_templates/` and a
`Tasks.base` view. It never overwrites existing files and is safe to re-run;
flags you pass update the config, flags you omit keep their current value.

| Key | Meaning |
|---|---|
| `BRAIN_WORK_VAULT` | Path to the work vault. |
| `BRAIN_PERSONAL_VAULT` | Path to the personal vault. The two vaults need no common parent. |
| `BRAIN_ROOT` | Alternative to the two paths above: a directory containing `work/` and `personal/`. |
| `BRAIN_OWNER` | Your name as it appears in your People note, e.g. `Maya Chen` → `People/Maya-Chen.md`. Required for writes. |
| `BRAIN_ORG_DOMAIN` | Optional. People with an email at this domain get `org: internal`. |
| `BRAIN_STATE_DIR` | Optional. Where the active-mode file lives (default `${XDG_STATE_HOME:-~/.local/state}/second-brain/`, or `BRAIN_ROOT` if set). |

The config file is plain `KEY=VALUE` lines. Every key can also be set as an
environment variable, and the environment wins over the file. If any vault
variable is set in the environment, vault paths come from the environment only.

## Command reference

The common commands and flags are listed below; `brain <command> --help` shows
every flag (for example `capture meeting --project/--summary-stdin`,
`capture task --context/--project/--source`, `extract-tasks --project/--source`,
`promote --week YYYY-Www`, `capture interview --summary-file`).

```
brain init     [--work-vault P] [--personal-vault P] [--owner NAME] [--org-domain D]
brain status
brain update   [--check] [--to TAG]   # the only command that uses the network
brain mode     [work|personal] [--because "<the user's words>"]

brain capture meeting   --title T [--date D] [--attendees "A, B"]
                        [--transcript-file F --summary-file S] [--decision TEXT]...
                        [--task "desc|area|priority|owner"]... [--followup "who|about"]...
brain capture interview --candidate NAME --role R --round N [--date D]
                        [--transcript-file F] [--assessment-file A] [--note TEXT]...
                        [--verdict pending|hire|no-hire]
brain capture task      --desc D --area client|internal|admin|learning
                        [--owner NAME] [--priority high|medium|low] [--this-week]
brain capture note      --title T --body-file F [--folder Reference|Content]
brain capture person    --name NAME [--org internal|external] [--role R] [--email E]
brain capture followup  --who NAME --about TEXT
brain extract-tasks     --task "desc|area|priority|owner"... [--title T --date D --transcript-file F]

brain promote --task SLUG...        # backlog -> this-week
brain done    --task SLUG...

brain query tasks [--status backlog|this-week|done] [--project SLUG] [--owner me|all|NAME]
brain query working-on | waiting-on | today
brain query person NAME
brain query project NAME
brain query meetings [--since YYYY-MM-DD]
brain query notes [TEXT]   # Reference/ and Content/ notes

brain lint   [--fix-safe] [--vault work|personal|both]
brain doctor [--vault work|personal|both]   # lint errors, broken links, orphans
```

Write commands print one `WROTE` / `UPDATED` / `UNCHANGED` / `LINKED` line per
note. A `MATCHED` line follows when a task request, worded differently, maps to
an existing task's filename: no second task is made, and the line names both
wordings. On a lint failure they print `file:field:problem`, write nothing, and
exit 1.

Dates must be real calendar dates in `YYYY-MM-DD` form; anything else is
refused with exit code 2. Person names must contain Latin letters: accents are
transliterated (`Inés` → `Ines`), but a name written only in another script
(e.g. `李雷`) is refused. Pass a romanized spelling instead.

The task `area` set (`client`, `internal`, `admin`, `learning`) is an
opinionated default for a consultant-style work life; change `ENUMS` in
`scripts/lib/core.py` (and the `--area` choices in `scripts/brain`) if it
does not fit you.

**Mode.** One vault is active at a time (default `work`). `brain mode personal`
only switches when `--because` quotes the user explicitly naming that vault
("switch to my personal brain"). This keeps an agent from moving notes between
vaults because a topic "feels personal".

## Vault schema (summary)

Folders: `Daily/ Meetings/ Transcripts/ Interviews/ Projects/ People/ Tasks/
Follow-ups/ Content/ Reference/` (+ `_templates/`).

Every note starts with:

```yaml
type: task        # matches its folder
schema: 1
created: 2026-08-15
tags: [task]
```

and opens with an `# H1` title (no `title:` in frontmatter). Tasks carry
`status`, `owner` (a `[[People/...]]` link), `project`, `area`, `priority`,
`source`; people carry `org: internal|external`, `role`, `email`; follow-ups
mean "I am waiting on `who`". See [docs/SCHEMA.md](docs/SCHEMA.md) for every
field, enum and naming rule.

## Development

```sh
bash tests/selftest.sh          # the CLI
bash tests/install-test.sh      # install.sh, under sh, dash and bash
bash tests/version-check.sh     # CLI, SKILL.md and CHANGELOG versions agree
pwsh -File tests/install-test.ps1   # install.ps1 (Windows)
```

Set `BRAIN_KIT_ONLINE_TEST=1` to also test the real download and `brain update`
against GitHub.

### Releasing

1. Bump the version in `scripts/brain` (`VERSION`) and in the SKILL.md
   `metadata.version`, and add a `CHANGELOG.md` entry.
2. Merge to `main` with CI green.
3. Tag and publish: `git tag -a v1.2.3 -m v1.2.3 && git push origin v1.2.3`,
   then `gh release create v1.2.3 --notes-file <notes>`. CI fails a tag that
   does not match the version.

The installers and `brain update` pick up a release as soon as it is published.
Users of `npx skills` follow `main`, so keep `main` releasable and do new work on
branches.

The self-test builds throwaway vaults under `.selftest-root/` (git-ignored,
deleted on exit; set `KEEP=1` to keep it), never touches your real config, and
exits non-zero on any failure. CI runs everything on Linux (Ubuntu and Alpine),
macOS and Windows via `.github/workflows/selftest.yml`.

Layout:

```
skills/second-brain/
  SKILL.md               # router + rules the agent follows
  references/sources.md  # rules for building commands from transcripts / notes
  scripts/brain          # CLI entry point
  scripts/lib/           # core (config, schema), capture, query, linter, writer, ...
  assets/templates/      # note body templates
tests/                   # selftest.sh, install-test.sh/.ps1, version-check.sh
install.sh, install.ps1  # installers
CHANGELOG.md
docs/SCHEMA.md
```

## License

[MIT](LICENSE) © 2026 Robus Gauli.
