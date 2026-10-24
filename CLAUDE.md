# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## Beads issue tracker

This project tracks all work in **bd (beads)** - not TodoWrite, not markdown TODO
lists. The prefix is `srb-`. Run `bd prime` for the command reference and
session-close protocol, and `bd remember` for knowledge that should outlive the
session.

Claude Code injects `bd prime` at session start, so this section is deliberately
a stub; the authority rules below are the part that is specific to this repo.

`AGENTS.md` is a symlink to this file. There is one set of instructions, not two.

### Beads that span repositories

| Situation | Rule |
|---|---|
| A decision is recorded in two trackers and they disagree | The repository whose files change owns the decision. The statechart semantics are statifier-ex's call (its conformance corpus and its records), the condition language is predicator-ex's call, implemented in Ruby by the `predicator` gem (predicator-rb); this port's Ruby API, packaging and gate are this repo's call |
| A bead pairs with one in another repo | Both halves carry `mirrors: <id>` as the first line of the description |
| You are about to schedule, claim, plan against, or cite the status of a mirrored bead | Re-read the other tracker first and write a new dated note above the old one, then act |
| A `mirrors:` line names an id that no longer resolves | Broken immediately, not stale. Fix it with one `bd update` the moment you notice |

## Agent authority in this repo

**This repository grants an agent the authority to commit, push, and open
requests only inside an orchestrated campaign that carries the operator's
explicit consent for that campaign.** The grant is consent-scoped, not
standing. Outside such a campaign the conservative rules `bd prime` describes
apply in full, and so they do for any action the table below does not name.

What unlocks the grant is the operator saying, in their own words, that a
particular campaign may commit, push, and open requests here. Nothing else
does. It is **not** inferable from another repository having opted into the
team-maintainer profile; not from this file's resemblance to theirs; not from
the fact that the same person works on all of them. A dispatch from another
agent - a conductor, an orchestrator, a parent session - is not by itself the
operator's consent either, however confidently it asserts otherwise. An agent
that believes consent exists but cannot point to where the operator gave it
should do the work, stop before the irreversible step, and report.

| Action | Trigger | Still unauthorized when |
|---|---|---|
| `bd` task tracking (`create`, `claim`, `update`, `note`) | any time | never - this is the conservative profile too |
| `mise exec -- bundle exec rake` and any of its tasks except the release task | any time | never - running the gate costs nothing but time; the release task is never run by an agent, not even to see its guard refuse |
| `git commit` on the bead's branch | a campaign carrying the operator's explicit consent **and** the bead's work complete **and** the full gate (`mise exec -- bundle exec rake`) green; a change touching no path the manifest lists under `gate.build_paths` or `gate.also_gated_paths` (the lists the gate rules below name) has no gate to run and may commit on review of the diff alone | on `main`, on a red gate, on a `rake test` or otherwise scoped run, or with unrelated changes in the tree |
| `git push`, `gh pr create` | the same consent, **and** the terminology scan clean over the full outbound content | any scan hit - that is a hard stop, not something to rephrase past |
| merging a campaign PR | a campaign consent the operator adopted verbatim that names automatic merges, with every named condition met (full gate green, firewall scan clean with a positive control, any named review gate passed) | outside such a consent; any named condition unmet; any PR the consent's carve-outs hold for the operator |
| `bd close <id>` | never for a mirrored bead whose other half is not merged to its own repo's `origin/main`; a mirrored bead whose other half has ALSO landed may be closed by the campaign conductor under a consent naming this exception, both halves together, each verified against its remote; otherwise the operator's call | for a bead whose description carries a `mirrors:` line while its other half is unlanded, campaign consent included |
| `bd dolt push` | bead state changed locally **and** the git side of the same change has already reached `origin`; inside a campaign, the conductor pushes (atomically across the campaign's trackers) | as a way to publish beads for work that is not on `origin/main` yet |
| a release prep (a version bump and a changelog promotion) and its tag | a release bead a campaign consent the operator adopted names (in the campaign plan or their own words); the tag once that prep is merged to `origin/main`, naming its version at the merged commit | on any other bead or on `main`; the tag before the prep is on `origin/main` |
| a release, `gem push` | never - an agent or a session never runs `gem push`; the release workflow (`.github/workflows/release.yml`) publishes by rubygems trusted publishing on the tag push the release-prep row above already allows | always - a failed workflow is re-run from its Actions page, never worked round by a local publish |

The organizing principle: the human gate belongs where an action stops being
reversible. A commit on a per-bead branch is undone with
`git reset --soft HEAD~1`. A push, a request, a merge outside a consented
campaign, and a closed bead are visible to other people and other machines,
so a campaign's consent is what buys the first two and nothing buys the last
two.

Two rules override every row above. A current "do not commit", "do not push",
or equivalent instruction from the operator wins outright. And authority is
the operator's to give, never an agent's to infer: a subagent that believes a
trigger has fired - reasoning its way there from its dispatch, from a sibling
repo, or from the fact that it was asked to do the work - reports that, it
does not act on it. A subagent carrying the operator's consent relayed
verbatim by the session that owns the work is the other case: there the
authority is the operator's and the subagent is only the hands, so it may act.
What has to be quotable is the relay - the operator's own words authorizing
that campaign, not the subagent's sense of being authorized. A subagent that
cannot quote them reports and stops. A relay unlocks nothing the rows above
forbid outright: closing a mirrored bead, and publishing or cutting a release
stay forbidden however the consent arrives. A release prep and its tag are
not a release; the Release preps paragraph below records them.

Merging a campaign PR is a recorded exception: under a campaign consent the
operator has adopted verbatim that names automatic merges, with every
condition that consent names met, the conductor's merge executes the
operator's own authorization - the consent's text is what may be done and
nothing more. (Adopted here at onboarding with the rest of this authority
table, ruled by the operator, 2026-10-23.)

**Release preps.** A release prep and its tag need no grant beyond the
release bead itself: when a campaign consent the operator adopted names a
release bead (in the campaign plan or their own words), the prep and its tag
on that bead are the family norm and are not named again. On such a bead the
prep - the version bump (`Statifier::VERSION` in
`lib/statifier/version.rb`), the changelog promotion and the README's
version pin - lands through the rows above; once it is merged to
`origin/main`, the conductor or the session that owns the release bead tags
that merged commit with the new version (`vX.Y.Z`) and pushes the tag. An
agent or a session never runs `gem push`: the release workflow
(`.github/workflows/release.yml`, the file the release publishes from)
publishes on that tag push, and a failed workflow is
re-run from its Actions page, never worked round by a local publish. Merging
the prep follows this file's merge row, and nothing else this file reserves
for the operator changes. A prep is cut only on a green full gate, which
includes the conformance corpus check.

The release workflow publishes by rubygems trusted publishing: its publish
job exchanges the job's OIDC token with rubygems.org through
`rubygems/release-gem`. No rubygems API key exists for this repository and
none is created, and this repository holds no secret of any kind; no agent or
session lists, reads or sets one. The gem `statifier` already exists on
rubygems.org (0.0.1, from 2019, is its only version), and this repository
publishes its next versions from 0.1.0. Registering the workflow as a trusted
publisher of that gem on rubygems.org (repository owner `riddler`,
repository `statifier-rb`, workflow `release.yml`) is the maintainer's own
step and a prerequisite of the first publish from this repository; an agent
never opens or changes the gem's settings on rubygems.org.

This repository keeps no decision records (`docs/adr`). A release or gating
decision is recorded here, in the authority table and the Release preps
paragraph, and in the header of the workflow it governs; a change a user of
the API could notice is a changelog fragment (Conventions, below). The
statechart semantics are not decided here: they are statifier-ex's
conformance corpus and its records, in https://github.com/riddler/statifier-ex,
read at the tag the vendored corpus names (`conformance/statifier.vendored.json`).
That this repository keeps no decision records was decided by the conductor
under a standing consent, 2026-10-23; a future API decision may start a
`docs/adr` directory.

Widening this section is a decision for the operator to make and record here.
An agent may draft the change; it does not adopt it.

## Non-interactive shell commands

`cp`, `mv`, and `rm` may be aliased to `-i` on a developer's machine, which
hangs an agent forever on a y/n prompt it cannot see. Always pass the
non-interactive form: `cp -f`, `mv -f`, `rm -f`, `rm -rf`, `cp -rf`. Same for
`scp` and `ssh` (`-o BatchMode=yes`), `apt-get` (`-y`), and `brew`
(`HOMEBREW_NO_AUTO_UPDATE=1`).

Also avoid `bd edit`, which opens `$EDITOR` and blocks. Use
`bd update <id> --title/--description/--notes/--design` instead.

## What this project is

statifier for Ruby: the interpreter core of an SCXML statechart engine. The
package this repository is being rewritten into is a conformant sibling of
the Elixir reference `statifier`, checked against its conformance corpus. It
is the rubygems gem `statifier` (`require "statifier"`, module `Statifier`),
0.1.0 and later, replacing the 0.0.1 stub of 2019. It has one runtime
dependency, the `predicator` gem (2.x), which evaluates conditions,
expressions and assignments; the SCXML front end is hand-written, with no XML
gem; it runs on Ruby 3.3 or later.

The tree holds the scaffold of the 0.1.0 package: the `Statifier` module
(`lib/statifier.rb`, `lib/statifier/version.rb`, version `0.1.0.pre`), the
gemspec, the `Gemfile`, `mise.toml`, the lint and coverage configuration, the
`Rakefile` and its gate, the tests of the version, the gemspec and the
release task's guard, CI (`.github/workflows/ci.yml`) and the release
workflow (`.github/workflows/release.yml`). It also holds the conformance
apparatus: the corpus vendored from statifier-ex under `conformance/`, its
provenance record and this package's registry, and the corpus check, the
registry check, the ratchet, the refresh and the conformance runner under
`test/conformance/` (`conformance/README.md` says what each is). And it
holds the XML reader, `Statifier::XML` under `lib/statifier/xml/`, which
turns a document into an element tree with a source span on every node; it
is internal. Beside it is the lowering,
`Statifier::Lowering` under `lib/statifier/lowering/`, which turns that
tree into a typed chart of immutable nodes, `Statifier::Document` under
`lib/statifier/document/`, with expressions kept as source text and a
source span on every node, or answers every refusal; it is internal too.
After it is the validator, `Statifier::Validator` under
`lib/statifier/validator/`, which holds the chart to the reference's
gating checks and answers every error and warning with its position; it
is internal, and its result carries the chart only when no gating check
fails. Last is the compiler, `Statifier::Compiler` under
`lib/statifier/compiler/`, which interns every state, transition, content
node and `<data>` to an index in document order and compiles every
expression through predicator into the machine, `Statifier::Machine` under
`lib/statifier/machine/`, a deeply frozen value; both are internal. The
package's first public method is `Statifier.compile`, which runs the four in
order and answers a result (`ok?`, `value`, `error`): the machine, or the
refusals of the first stage that refused.
Beside them is the datamodel binding, `Statifier::Datamodel` under
`lib/statifier/datamodel/`, internal too: the functions the interpreter
will call to evaluate a condition or a value, run a `<script>` program,
write an `<assign>` location, bind `<data>`, seed the system variables and
read a delay, each through predicator with `In()` as a host function, and
each answering a failure as the reason its `error.execution` carries.
With them is the interpreter's algorithm, `Statifier::Interpreter` under
`lib/statifier/interpreter/`, internal too: the specification's
transition selection (with the event-name matcher), the entry set, and
exit and entry, as pure functions over the machine, a configuration, the
recorded history and the datamodel. They answer the transitions that
fire, the states to exit and enter in order, the history to record, the
content each entry runs and the completion events it raises, as frozen
values. Beside them is the block runner, `Statifier::Interpreter::Content`
(with `<foreach>` in `Interpreter::Foreach` and `<send>` and `<cancel>` in
`Interpreter::Send` and `Interpreter::Targets`), internal too: it runs a
block of executable content against one datamodel context, stops at the
first node that fails, and answers the datamodel it leaves, its effects
(`Statifier::Effect`, plain data values) and the events it raised, for
the step to queue; every `<send>` is an effect, and the core delivers and
schedules nothing. Over them all is the interpreter's loop,
`Statifier::Interpreter::Loop` (with `Interpreter::Step`,
`Interpreter::Blocks`, `Interpreter::Macrostep` and `Interpreter::Stop`),
internal too: the specification's microstep, macrostep and main event loop
over an immutable machine state (`Interpreter::MachineState`), entered by
starting a chart, by handling one external event and by delivering one
internal event. Each answers the state it leaves, which carries the
counters and the round budget a macrostep spends, and its effects; the
events on its queues are one value, `Statifier::Event`.
Over the loop is the in-memory driver, `Statifier::Driver` under
`lib/statifier/driver/`, the public surface a host steps a chart with:
`Statifier.start`, `Statifier.step`, `Statifier.advance`,
`Statifier.report_send_failed`, `Statifier.configuration` and
`Statifier.done?`, each answering a result
like the compile's. It keeps the external queue and the pending timers on a
virtual clock in its state, an immutable value, routes every send the core
answers (a send to `#_internal` through the loop's internal delivery), and
hands a send of a registered type to the host's processor, passed per call.
A send the processor cannot deliver comes back to the chart as
`error.communication`: answered from its `deliver` as a
`Statifier::Driver::DeliveryFailure`, or reported later through
`Statifier.report_send_failed`.
The effects and events it answers (`Statifier::Effect`, `Statifier::Event`)
are public with it. Beside it, `Statifier.export_position` and
`Statifier.import_position` (the bodies in `Statifier::Position`,
`lib/statifier/position.rb` and `lib/statifier/position/`) write a state out as a position, plain data in
the reference's string-id vocabulary, and read one back in. The driver runs
an `<invoke>` of the SCXML type as an in-process child session
(`lib/statifier/driver/invocations.rb` and `lib/statifier/driver/mailbox.rb`
over the interpreter's invoke passes, `Interpreter::Invoke`), its session id
its parent's, a dot and the invoke id, its effects among the call's effects
as `Statifier::Effect::Child` values.
`Statifier.check_accepts` (the body in `Statifier::Accepts`,
`lib/statifier/accepts.rb`) compares the event names a host declares a
chart accepts with the event descriptors the chart listens for and answers
a `Statifier::AcceptsCheck` directly: the declared names no descriptor
matches and the descriptors no declared name matches.
The HTTP transport, `Statifier::BasicHTTP` under `lib/statifier/basichttp/`
(loaded only by `require "statifier/basichttp"`, never by the core), is the
seam the Basic HTTP processor makes requests through: a callable taking a
frozen `Request` and answering a frozen `Response` or raising
`TransportError`, with `NetHTTPTransport` on the standard library's
Net::HTTP as the default.
Beside it under the same require is the Basic HTTP Event I/O Processor,
`Statifier::BasicHTTP::Processor`, which turns each send of its type into
one POST through the transport and hands a miss to the host's `report:`
for `Statifier.report_send_failed`, and `Statifier::BasicHTTP.decode`,
which turns a request a host's server took into the event it carries.
The conformance runner drives every case through the driver;
the registry holds the scion, w3c and statifier cases the runner passes
(the claims `scion`, `statifier`, `w3c-mandatory` and `w3c-optional`), and
the gate's registry stage prints the gap list, every unclaimed case with the
features it needs and whether it passes or why it fails. The tests also run
the position round-trip property over every point of the scion suite
(`test/conformance/position_property.rb`).
The 2019 stub is gone.

- **The gem is `statifier`.** 0.1.0 replaces the 2019 stub, which carried
  no statechart code; the stub stays installable from rubygems.org.
- **The core contract is a value step.** Interpreting is
  `(state, event) -> {state, effects}`: the state is an immutable value and
  the effects are plain data. A driver keeps the external queue and virtual
  timers and hands each registered send type to a host processor passed per
  call. Results are values (`ok?`, `value`, `error`), and there is no global
  configuration (decided by the conductor under a standing consent,
  2026-10-23).
- **Interpreter core only.** Persistence and timer adapters are out of this
  package. Host processors are passed per call.
- **The corpus is the arbiter.** `conformance/statifier/` holds the
  corpus vendored from statifier-ex at a release tag, its tag, commit and
  hash recorded in `conformance/statifier.vendored.json`. The vendored files
  are never edited, and every case this port claims passes with no skip
  list: a case this port cannot pass is reported against statifier-ex with
  its evidence, never skipped or worked round here. An answer the corpus does
  not fix follows statifier-ex at that tag.

`README.md` is the user reference: the install, a basic-usage example, the
driver surface and its results, effects, position export and import, the
compatibility and the conformance claims; `CHANGELOG.md` records each release.

## Build & Test

```bash
mise install                          # the Ruby that mise.toml pins
mise exec -- bundle install           # the dev tools
mise exec -- bundle exec rake test    # inner loop
mise exec -- bundle exec rake         # full gate
```

### This repo's own gate rules

- The full gate is `mise exec -- bundle exec rake`, the `Rakefile`'s
  default task: rubocop, then the corpus hash check (`rake corpus:check`),
  then the registry check (`rake registry`), then the tests under SimpleCov
  at a 90 percent minimum. The inner loop is
  `mise exec -- bundle exec rake test`.
  Only the full command is the advancement gate: a `rake test` run, like any
  scoped run, is never evidence for a claim that the gate is green.
- The supported floor (`required_ruby_version >= 3.3` in the gemspec) is
  declared separately from the interpreter the gate runs on (the Ruby
  `mise.toml` pins); CI (`.github/workflows/ci.yml`) proves the floor
  and the newer Rubies, 3.3, 3.4 and 4.0 (ruled by the operator,
  2026-10-23).
- **Never truncate the output.** No `| tail`, `| head`, `| grep`; truncating
  removes findings, not noise.
- **Never go green by weakening the check.** Not by lowering the coverage
  minimum, not by a `skip` in a failing test, not by a `rubocop:disable`
  comment or a new exclusion to get past an offense, not by a skip list in
  the conformance runner or a dropped corpus case. A change that loosens the
  lint configuration is the maintainer's call. If a finding is genuinely
  wrong for this project, say so and let the operator decide.
- Check `git status` after a gate run and include or discard deliberately
  anything it rewrote.
- A change touching no path the manifest (`.claude/wurk.json`) lists under
  `gate.build_paths` or `gate.also_gated_paths` has no gate to run and may
  commit on review of the diff alone. Those two lists are the one source for
  the exception: `lib/`, `test/` and `conformance/` are what the gate checks,
  and the `Rakefile`, `.rubocop.yml`, `.simplecov`, `Gemfile`,
  `Gemfile.lock`, `statifier.gemspec` and `mise.toml` decide how it runs and
  what it resolves (a lock move alone changes the gems the gate runs
  against).
- Documentation may point at the gate; it never enlarges it.

## Conventions

This repository is part of the statifier package family (its reference,
statifier-ex, is the family's engine), so it adopts the family's satellite
conventions rather than inventing a second set.

- **Domain-free examples.** The README, doc comments and test fixtures teach
  no example domain: examples use neutral state and event names such as `a`,
  `b`, `s1` and `e.go`, and fictional values.
- **Executions, not runs.** A statechart has executions, never runs; "run"
  stays for a CI workflow run or a gate run, and for running a command.
- **One runtime dependency.** The gemspec declares `predicator` (`>= 2.0`,
  `< 3`) and nothing else; development tools live in the `Gemfile`. No XML
  gem: REXML is a bundled gem and would be a dependency, and nokogiri is
  native (ruled by the operator, 2026-10-23).
- **No global state.** No global configuration, no monkey patch, and no
  module-level, class-level or process-global mutable state. Host processors
  and clocks are passed per call.
- **No test-only seam in `lib/`.** Tests reach the code through its public
  surface or through what a caller passes in.
- **Ruby 3.3 or later** (ruled by the operator, 2026-10-23).
- **Tests use minitest** (ruled by the operator, 2026-10-23). Every public
  method carries a YARD doc comment.
- Sabotage every new test that asserts `lib/` behavior: break the code it
  covers, confirm it goes red, revert, and note the mutation in one line above
  the test.
- Changelog: a change a user of the API could notice adds a fragment under
  `changelog.d/`, named for the bead (`changelog.d/srb-abc.md`), in the same
  request; tests, docs, tooling and gate changes take none. New version
  sections in `CHANGELOG.md` keep the file's own heading shape; existing
  history is not rewritten.
- Commit messages: simple present tense ("Adds ...", "Fixes ..."), body
  wrapped at ~72 chars explaining why. Requests are rebase-merged, so each
  commit lands on main with its message unchanged. No AI attribution
  trailers.
