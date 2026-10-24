# Changelog fragments

Changelog entries for unreleased work live here, one file per issue, not as
edits to `CHANGELOG.md`. At release the fragments are assembled into one
version section of `CHANGELOG.md` and deleted.

## Why fragments

Work happens in one worktree per issue, so several branches are usually open
at once. If each appended to the top of `CHANGELOG.md`, every branch would
touch the same lines of the same file and nearly every pull request would
conflict with every other. A fragment is named for its issue, so no two
branches write the same file.

## When a change needs a fragment

The changelog serves people who use the gem. Write a fragment for a change a
user of the API could notice:

- a public method, option, constant or class added, changed or removed
- a change in observable behavior, including the configuration an execution
  reaches, the effects a step returns or the error it reports
- a bug fix a user could have noticed
- anything breaking

Write none for tests, documentation, tooling, CI or gate changes. If you are
unsure, ask whether someone who only calls the public API could tell the
difference; if not, skip it.

## Format

One file per issue, named for its beads issue id, in the same pull request as
the change:

    changelog.d/srb-abc.md

The file holds a Keep a Changelog kind heading and one bullet per change:

```markdown
### Added

* `Statifier.example(chart)` does one thing a user can now rely on.
```

- The kind headings are `### Added`, `### Changed`, `### Deprecated`,
  `### Removed`, `### Fixed` and `### Security`. A file may carry more than
  one when the issue genuinely spans them.
- Bullets are `* `, one per change, in the present tense, saying what the
  change means to a user. No nested bullets: detail belongs in the pull
  request and the commit body.
- A breaking change opens its bullet with `Breaking:` and says what a caller
  does about it, not only what broke.
- Examples stay domain-free: neutral state and event names such as `a`, `b`,
  `s1` and `e.go`, and fictional values.

## At release

The release prep assembles the fragments into a new version section at the
top of `CHANGELOG.md`'s history, below `### Upcoming`, headed
`### X.Y.Z / YYYY-MM-DD` at the level `### Upcoming` already has. The entries
are grouped by kind in the order Added, Changed, Deprecated, Removed, Fixed,
Security, each kind under a bold label (`**Added**`) because the version
heading already holds the `###` level; a `Breaking:` bullet keeps that word.
The sections already in `CHANGELOG.md` are not rewritten. The fragments are
deleted in the same commit.

The prep (the version bump in `lib/statifier/version.rb`, the promoted
section, the README's version pin and the deleted fragments) merges on its
own, and then its merged commit is tagged `vX.Y.Z`. The release workflow,
`.github/workflows/release.yml`, publishes on that tag push (CLAUDE.md,
"Release preps"). Because the prep consumes every fragment, it merges last:
a branch still holding an unmerged fragment when the prep lands waits for
the next release.
