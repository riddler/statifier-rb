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
into the run. This package has no interpreter yet, so today the drive
answers every case with the reason that it is not driven, the run passes
nothing, and every case is unclaimed.

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
whole corpus. There is no command that adds a case by id. With nothing
passing, it writes the registry it found.

**Registry check.** `rake registry` runs the checks under "The check" in the
copy's `RATCHET.md` - the pin, rule 1, the claims, every entry passing in a
run made now, and something to check - and refuses entries out of order, a
case entered twice, another implementation's name and a file the ratchet
would not have written. Before the first entry the registry carries the pin,
no claims and no entries, and the check says that no claim is made. The
copy's `schema/registry.json` refuses that file, since an empty registry
makes no claim; it stays this registry's shape until a run passes a case.

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
