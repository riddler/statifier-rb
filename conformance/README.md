# conformance/

How this package holds itself to the conformance corpus of statifier-ex, the
Elixir reference implementation. The corpus is the arbiter: a case this
package answers differently from the corpus is this package's bug.

| Path | What it is | Written by |
|---|---|---|
| `statifier/` | statifier-ex's `conformance/` directory at the tag the provenance record names, byte for byte (below) | `rake corpus:refresh`, never by hand |
| `statifier.vendored.json` | the provenance record: the upstream repository, the tag, the commit the tag resolves to, and the corpus hash recomputed from the copy, as one line of JSON | `rake corpus:refresh` |
| `registry.json` | this package's registry: the corpus cases it claims to pass, against the pinned corpus | `rake ratchet`, never by hand |
| `README.md` | this file | hand, reviewed like code |

The last three rows are this repository's own. Everything under `statifier/`
is copied.

## What is copied, and from where

The copy is the `conformance/` directory of
https://github.com/riddler/statifier-ex at the tag and commit
`statifier.vendored.json` records, taken by the sequence under "Vendoring the
corpus" in the reference's [`RATCHET.md`](statifier/RATCHET.md) with `DEST`
set to `conformance/statifier`: every file under `conformance/` at the tag,
written as git stores it. That is:

- the three suite files, `corpus/scion.json`, `corpus/w3c.json` and
  `corpus/statifier.json`, and `manifest.json`, which names them, gives each
  suite's case count and carries the corpus hash;
- the JSON Schemas under `schema/`;
- the cases the reference authors itself, under `cases/`;
- `exclusions.json`, the upstream documents the reference leaves out of the
  corpus, each with its reason;
- the reference's own `README.md`, `RATCHET.md` and `registry.json` (the
  reference's claim, never this package's);
- `LICENSES/`, the licence texts the upstream cases are redistributed under.

What each of those files is, and who writes it upstream, is the reference's
[`README.md`](statifier/README.md); the contract this package's registry is
written against is its `RATCHET.md`. Both are read in the copy, at the tag,
never at the reference's `main`.

**The copied files are never edited.** Re-running the sequence at the same
tag reproduces the copy exactly, so a copy that differs from a fresh run has
been edited. The fix for a copied file that is wrong is upstream, followed by
a refresh to the tag that carries it.

**The licences travel with the copy.** The `scion` suite's cases come from
the SCION scxml-test-framework and are redistributed under the Apache License
2.0 (`statifier/LICENSES/Apache-2.0.txt`); the `w3c` suite's come from the
W3C SCXML Implementation Report Plan test suite and are redistributed under
the W3C 3-clause BSD License (`statifier/LICENSES/BSD-3-Clause-W3C.txt`). The
copy's `manifest.json` names each upstream suite with its licence and notice
file, and each case's `upstream` field names its upstream document, its
licence and its notice. The `statifier` suite is the reference's own.

The copy is not part of the gem: the gemspec packages `lib/` and the
top-level documents only.

## The commands

```bash
mise exec -- bundle exec rake corpus:check          # the four hashes agree (a gate stage)
mise exec -- bundle exec rake registry              # the registry check (a gate stage)
mise exec -- bundle exec rake ratchet               # record in registry.json the cases a run made now passes
mise exec -- bundle exec rake "ratchet[scion]"      # the same, adding the passes of the named suites only
mise exec -- bundle exec rake "corpus:refresh[TAG,CLONE]"   # move the copy to a tag
```

The code behind them lives in `test/conformance/`, beside the tests that hold
it; none of it ships.

**Check.** `rake corpus:check` recomputes the corpus hash from the copy -
SHA-256 over the bytes of the suite files concatenated in suite order, scion,
w3c, statifier - and requires it to equal four fields: the vendored
manifest's `corpus_hash`, the provenance record's, this registry's and the
vendored reference registry's. It also requires every suite file the
manifest lists to be there with the case count the manifest gives. A mismatch
fails naming the field, and is never repaired by rewriting a hash: restore
the copied bytes, or refresh the copy to a tag.

**Run.** The conformance runner is a test of the suite
(`test/conformance/runner_test.rb`). It reads every case of every suite with
no skip list, refuses a case carrying a key the copy's `schema/case.json`
does not name (at every object the schema closes), hands every case to the
drive, requires every case this registry claims to pass, and prints per
suite how many cases are not yet claimed. The drive (`Conformance::Drive` in
`test/conformance/runner.rb`) is the one place the interpreter is plugged
into the run. It drives each case through the package's driver
(`Statifier.start`, `Statifier.step` and `Statifier.advance`) on a virtual
clock that settles 100 virtual milliseconds before each event and waits at
most 4000 virtual milliseconds after it, the two knobs of the reference's
harness. A case's `host.event_io_processors` names the Event I/O
Processors its host runs: the drive registers with the driver every
processor its table (`Conformance::Drive::PROVIDED`, keyed by the URI the case
names, empty until the package provides one) holds for a named URI, and fails
a case naming a URI the table does not hold, naming that URI. A case's
`host.send_types` and `host.expect_sends` are read as the reference's
host-case harness reads them: a host of the case's own
(`Conformance::Host` in `test/conformance/host.rb`) is registered under
every send type the case names, from the start of the chart, and records
each send the driver hands it, in the case's item shape, delivering none;
once every configuration agrees, the sends handed over the whole drive, in
order and each with its outcome, must be exactly `expect_sends`. A
`<cancel>` that reaches the host marks the delayed send it names
`"outcome": "cancelled"` when the expected item at that send's position
asks for it, and a step of a case with a host object, or of a case stating
an exported position, sends its event's `data`, when it gives one. A send
whose expected item asks the host to
report it failed (`"outcome": "fail"`) is marked so and reported through
`Statifier.report_send_failed` once the driver call that handed it returns,
before the configuration is read, as the reference's harness reports it
before it reads the next configuration; a report the driver refuses because
the chart has stopped is dropped. A case's `host.declared_events` and
`host.expect_accepts` are read as the reference's harness reads them:
`Statifier.check_accepts` answers for the compiled chart before it starts,
and its two lists must be exactly `expect_accepts`. A host object's diff
pair, `to_source` and `expect_diff` with an optional `mapping` and
`expect_compatible_at`, is compared by nothing here, as the reference's
harness compares none of the four: a case carrying it is driven like any
other host case, and agrees on its configurations and its sends. A step's
`expect_position` is compared, once that step's configuration agrees, with
the state's position exported through `Statifier.export_position` and
rendered as the reference's harness renders it
(`Conformance::PositionExpectation` in
`test/conformance/position_expectation.rb`): the configuration, the entered
states and the states to invoke, each sorted; each history state's recorded
states, sorted; each active invocation as its state and index, sorted; the
running flag; and the datamodel without `_event`, `_ioprocessors` and
`_sessionid`, and without `_name` unless the `<scxml>` element carries a
`name` attribute, each value in its JSON form. A date, a datetime or a
duration has no JSON form and fails the step naming its variable, and a
case stating a position on a document with a state that has no id fails
before it is driven. Any other host key fails the case naming it. This
registry claims the scion suite, every one of its cases, the w3c cases the
run passes and every case of the statifier suite: the `w3c-mandatory`
claim covers its mandatory entries, the `w3c-optional` claim its optional
ones and the `statifier` claim its statifier entries, since a claim is the
set of its entries (the copy's `RATCHET.md`, "Claims"), not a statement
that every case of the suite passes. The w3c cases left out are the two
mandatory cases the run fails and the optional cases whose host object
names the BasicHTTP processor, which the drive does not provide. Beside the
drive, the position round-trip
property (`test/conformance/position_property.rb`), a test of the gate,
takes a point after the start and after every step of each scion case,
exports the position there, carries it through JSON, imports it into a fresh
compile and drives the remaining steps, requiring the imported drive to agree
with the unbroken one at every later step; it is this package's claim about
itself, not a comparison with the reference's positions.

An excluded document is not in the corpus at all, so it is not a case and
is counted nowhere; `exclusions.json` is copied for its reasons. A case in
the corpus that this registry has no entry for is unclaimed, whether or not
the reference claims it.

**Ratchet.** `rake ratchet` runs the whole corpus now and writes the union of
the recorded entries and the cases the run passed, pinned to the vendored
manifest's hash, with exactly the claims those entries count toward, one
entry per line in the reference's encoding. It refuses, writing nothing,
when an entry already recorded did not pass, when it is recorded under
another suite or the corpus does not hold it, and when the run is not of the
whole corpus. `rake "ratchet[scion]"` still runs the whole corpus but adds
only the passes of the suites it names. There is no command that adds a case
by id. With nothing passing, it writes the registry it found.

**Registry check.** `rake registry` runs the checks under "The check" in the
copy's `RATCHET.md` - the pin, rule 1, the claims, every entry passing in a
run made now, and something to check - and refuses entries out of order, a
case entered twice, another implementation's name and a file the ratchet
would not have written. Before the first entry the registry carries the pin,
no claims and no entries, and the check says that no claim is made. The
copy's `schema/registry.json` refuses that file, since an empty registry
makes no claim; that was this registry's shape until a run passed a case.
The stage then prints the gap list: one line per case the registry does
not claim, in the reference's order, with the features it needs and either
"passes, not yet claimed" or why it fails in the run.

**Refresh.** Moving the copy to another tag is a change of its own, reviewed
like code. `rake "corpus:refresh[TAG,CLONE]"` reads the tag from `CLONE`, a
clone of statifier-ex (for one, `git clone --bare
https://github.com/riddler/statifier-ex`), refuses while the copy or its
record has uncommitted changes, refuses a name that is not a tag, writes the
copy into a temporary directory, requires it to hash to its manifest's hash,
and only then replaces `statifier/` and rewrites the provenance record, which
names the public repository, never the clone. A new tag changes the corpus
hash: the corpus check then fails on this registry's pin until
`rake ratchet` re-verifies every entry against the new corpus and re-pins
it.
