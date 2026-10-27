# Changelog

All notable changes to brain-kit. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- A task request that maps to an existing task's filename is no longer
  dropped silently. An explicit priority (`--priority`, or the third field of
  `--task`) now updates the existing task, and different wording prints a
  `MATCHED` line naming the existing task. Before this, both cases printed
  `UNCHANGED`. A `--task` spec with no priority no longer resets an existing
  task to `medium`.

## [1.1.0] - 2026-10-27

### Added
- `brain query notes [TEXT]` finds notes in `Reference/` and `Content/`.
  Before this, `capture note` wrote these notes but no query read them, and
  the skill forbids direct vault reads. One match prints the whole note.

## [1.0.1] - 2026-10-27

### Changed
- The installers (`install.sh`, `install.ps1`) now install the **latest
  GitHub release** instead of the `main` branch. Pin a version with
  `BRAIN_KIT_REF=v1.0.1` (or `sh -s v1.0.1`). If the latest release cannot be
  found, the installer stops with an error. It never falls back to `main`.
- The installers print a `source:` line naming the release they installed.

### Added
- `brain update` installs the latest release in place. `brain update --check`
  only reports whether one exists. `brain update --to <tag>` installs a
  specific release (pin or roll back). This is the only command that uses the
  network, and it runs only when you ask.
- The installers write a receipt, `install.json`, next to the installed skill
  (version, source, method, date).
- `metadata.version` in the SKILL.md frontmatter.
- This changelog. CI checks that the CLI version, `metadata.version`, the
  newest changelog entry and the release tag all agree.

## [1.0.0] - 2026-10-27

### Added
- First release: the `second-brain` skill and its CLI, installers for macOS,
  Linux and Windows, and CI on all three.

[1.1.0]: https://github.com/RobusGauli/brain-kit/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/RobusGauli/brain-kit/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/RobusGauli/brain-kit/releases/tag/v1.0.0
