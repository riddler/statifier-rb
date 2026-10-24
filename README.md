# Statifier

[![MIT License][badge_license_url]](LICENSE)
[![CI][badge_ci_url]](https://github.com/riddler/statifier-rb/actions/workflows/ci.yml)

The interpreter core of an SCXML statechart engine, for Ruby. Give it a chart
and an event and it answers the chart's next configuration and what the host
should do about it, as plain data. The reference implementation is
[statifier-ex](https://github.com/riddler/statifier-ex), written in Elixir,
and this gem is checked against that implementation's conformance corpus.

## Why this package

A chart is authored once and should decide the same way wherever it runs. This
gem is the same algorithm as the reference, held case by case to the
reference's conformance corpus, with no process, no real clock, no I/O and no
storage of its own: state is an immutable value, a step is
`(state, event) -> (state, effects)`, and the effects are plain data. A host
keeps the state however it likes, delivers what a chart sends, and passes its
own processors and clock with each call. Persistence, a real clock and
delivering a send stay the host's.

## Install

Add `statifier` to your Gemfile:

```ruby
gem "statifier", "~> 0.1"
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install statifier

The constraint matches the 0.1 series, which begins with the 0.1.0 release of
this rewrite. The 0.0.1 version on rubygems.org is a stub from 2019 that
carries no statechart code, and the constraint excludes it.

The gem has one runtime dependency, [`predicator`](https://github.com/riddler/predicator-rb)
(`>= 2.0`, `< 3`), which evaluates the conditions, expressions and script
bodies a chart carries.

## Basic usage

A host compiles a chart once and drives it with the other calls. The chart
below starts in `a`, where it arms a ten-second timer; the timer moves it to
`b`, `e.inc` counts, and `e.go` stops it in the final state `c`, answering the
count. Every Ruby example on this page is run against the code in this
repository, and a line ending in `# =>` is an assertion that the value on its
left equals the value on its right.

```ruby
require "statifier"

source = <<~SCXML
  <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0" initial="a">
    <datamodel><data id="count" expr="0"/></datamodel>
    <state id="a">
      <onentry><send id="t" event="e.timeout" delay="10s"/></onentry>
      <onexit><cancel sendid="t"/></onexit>
      <transition event="e.inc" target="a"><assign location="count" expr="count + 1"/></transition>
      <transition event="e.timeout" target="b"/>
      <transition event="e.go" target="c"/>
    </state>
    <state id="b"><transition event="e.go" target="c"/></state>
    <final id="c"><donedata><param name="count" expr="count"/></donedata></final>
  </scxml>
SCXML

# Compile once: the machine is a frozen value, shared by every execution
compiled = Statifier.compile(source)
compiled.ok? # => true
machine = compiled.value

# The host names the session; each call answers a result holding the state and its effects
started = Statifier.start(machine, session_id: "s1")
started.value.effects.map { |effect| effect.class.name.split("::").last } # => ["DatamodelInit", "DatamodelChange", "SendDelayed"]
Statifier.configuration(started.value.state).value # => ["a"]

counted = Statifier.step(started.value.state, "e.inc")
Statifier.configuration(counted.value.state).value # => ["a"]

# advance moves the virtual clock and fires every timer due by then
lapsed = Statifier.advance(counted.value.state, 10_000)
Statifier.configuration(lapsed.value.state).value # => ["b"]

stopped = Statifier.step(lapsed.value.state, "e.go")
Statifier.done?(stopped.value.state).value.done # => true
Statifier.done?(stopped.value.state).value.donedata # => { "count" => 1 }
Statifier.done?(stopped.value.state).value.configuration # => ["c"]
```

## The driver surface

Ten calls make up the public surface. Nine of them answer a
`Statifier::Result`, which has `ok?`, `value` and `error`. A successful result has `error == nil`
and a failed one has `value == nil`; read `ok?` and not the value.

| Call | Answers, in the result |
|---|---|
| `Statifier.compile(source)` | the machine, or the refusals of the first stage that refused |
| `Statifier.start(machine, **options)` | a `Statifier::Driver::Moved`: the `state` and the `effects` of starting the chart |
| `Statifier.step(state, name, data:, processors:, clock:)` | a `Moved`, after one external event and every event the chart queues for itself; `:not_running` once the chart has stopped |
| `Statifier.advance(state, milliseconds, processors:, clock:)` | a `Moved`, after the virtual clock moves and every timer due fires, earliest first; `:invalid_duration` for a negative, infinite or non-numeric duration |
| `Statifier.report_send_failed(machine, state, send, **options)` | a `Moved`, after the chart takes `error.communication` for a send the host could not deliver; `:not_running` once the chart has stopped, `:halted` while a round budget has halted it |
| `Statifier.configuration(state)` | the active state ids, sorted, as a frozen list |
| `Statifier.done?(state)` | a `Statifier::Driver::DoneStatus`: `done`, and once the chart has stopped its `donedata` and `configuration` |
| `Statifier.export_position(state)` | the position, plain data ready for JSON, or a `Statifier::Position::Refusal` |
| `Statifier.import_position(machine, position, processors:)` | a state, or a `Position::Refusal` |

The tenth, `Statifier.check_accepts(machine, declared_events)`, refuses
nothing and answers a `Statifier::AcceptsCheck` directly (below).

`start` takes these options, each optional: `session_id:` (the id `_sessionid`
reads; the driver mints one when it is absent), `datamodel:` (starting values
for the datamodel), `processors:`, `max_macrostep_rounds:` (a positive Integer
or `:infinity`; 10000 when absent), `trace:` (whether the chart answers trace
effects; false when absent) and `clock:`. The state is an immutable value that
a call answers and the next call takes; a host reads it only through
`configuration` and `done?`, and its members are internal.

### Declared events

`Statifier.check_accepts` compares the event names a host declares a chart
accepts with the event descriptors the chart listens for, on its transitions
from every state some path can enter. A descriptor matches a name as
transition selection matches an event: `e`, `e.`, `e.*` and `*` all match
`e.go`, and `e.gone` does not. It answers two frozen lists:
`unreachable`, the declared names no descriptor matches, in the declaration's
order; and `undeclared`, the descriptors that match no declared name, in
document order. With `nil` for the declaration both lists are empty.

```ruby
machine = Statifier.compile(<<~SCXML).value
  <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0">
    <state id="a"><transition event="e.go" target="b"/></state>
    <state id="b"><transition event="e.back" target="a"/></state>
  </scxml>
SCXML

check = Statifier.check_accepts(machine, ["e.go", "e.stop"])
check.unreachable # => ["e.stop"]
check.undeclared  # => ["e.back"]
```

### Refusals

A call never raises for something a chart or a source does. A refusal is a
value:

```ruby
stopped = Statifier.step(lapsed.value.state, "e.go")
Statifier.step(stopped.value.state, "e.go").error # => :not_running
Statifier.advance(lapsed.value.state, -1).error # => :invalid_duration
```

`Statifier.compile` answers the list of refusals of the first of four stages
that refused the source: the XML reader (`Statifier::XML::ParseError`), the
lowering (`Statifier::Lowering::Error`), the validator
(`Statifier::Validator::Error`) and the compiler (`Statifier::Compiler::Error`,
when predicator refuses an expression). Each carries a `reason` symbol, a
`message` for a person and a `location`, the span of the source it names:

```ruby
Statifier.compile("<scxml>").error.first.class # => Statifier::XML::ParseError
Statifier.compile("<scxml>").error.first.reason # => :unclosed_element

unresolved = Statifier.compile(<<~SCXML)
  <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0">
    <state id="a"><transition event="e.go" target="zz"/></state>
  </scxml>
SCXML
unresolved.error.first.class # => Statifier::Validator::Error
unresolved.error.first.reason # => :unresolved_target

badcond = Statifier.compile(<<~SCXML)
  <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0">
    <state id="a"><transition event="e.go" cond="1 +" target="a"/></state>
  </scxml>
SCXML
badcond.error.first.class # => Statifier::Compiler::Error
badcond.error.first.reason # => :expression_compile_error
```

A validator warning never refuses: a chart that compiles carries its warnings
on the machine, `machine.warnings`, in document order.

A bug in the call itself raises: a `TypeError` for an argument of the wrong
kind (a state that is not a driver state, an event name that is not a String)
and an `ArgumentError` for an option the call does not name or processors that
register other send types than the chart started with.

## Effects as data

Every effect a call answers is a frozen `Data` value under `Statifier::Effect`,
named for what the host does with it. The reference's vocabulary is ported
field for field, and each effect carries the `macrostep`, `microstep` and
`round` counters as they stood when it was made. The ones a host most often
reads:

| Effect | What the host does with it |
|---|---|
| `Send` | delivers the event now, by its `target` and `type` |
| `SendDelayed` | learns of an event due later; the driver holds it as a pending timer until `advance` reaches it |
| `Cancel` | learns that the pending delayed send its `send_id` names is dropped |
| `Log` | records the label and the evaluated value |
| `DatamodelInit`, `DatamodelChange` | learns the datamodel as the chart starts, and each write after |
| `Invoke`, `CancelInvoke`, `Autoforward` | learns of an invocation the core starts, stops or forwards an event to |
| `BudgetExhausted` | learns that a macrostep spent its round budget; the chart keeps running |
| `Done` | learns that the chart stopped, with the top-level final's donedata |
| `Child` | wraps an effect an invoked child's execution answered, with the child's `session_id` |

The `Trace` effects follow the interpreter step by step and are answered only
for a chart started with `trace: true`. An event is a `Statifier::Event`, the
one value every queue holds.

The driver delivers nothing itself that leaves the process. A send of a type
the host registers is handed to the host's processor, an object that answers
`deliver(send, event, context)` (and, optionally, `cancel(cancel, context)`).
Processors are passed per call, by send type, and name the same types for the
whole life of a chart; they are never stored in the state:

```ruby
class Outbox
  attr_reader :seen

  def initialize = @seen = []

  def deliver(send, event, context) = @seen << [send.target, event.name, context.session_id]
end

notify = Statifier.compile(<<~SCXML).value
  <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0">
    <state id="a">
      <transition event="e.go" target="b"><send type="outbox" event="e.out" target="t1"/></transition>
    </state>
    <state id="b"/>
  </scxml>
SCXML

outbox = Outbox.new
processors = { "outbox" => outbox }
waiting = Statifier.start(notify, session_id: "s1", processors:)
sent = Statifier.step(waiting.value.state, "e.go", processors:)
outbox.seen # => [["t1", "e.out", "s1"]]
sent.value.effects.map { |effect| effect.class.name.split("::").last } # => ["Send"]
```

A send a processor cannot deliver comes back to the chart as
`error.communication`, its `sendid` the send's id whether or not the author
named it. A processor that knows while it is handed the send answers
`Statifier::Driver::DeliveryFailure.new(reason: ...)` from `deliver`, and the
chart takes the error within that call. A host that learns of the miss later
reports it with the send it was handed; the reason is the host's own and the
chart is not handed it:

```ruby
failed = Statifier.report_send_failed(notify, sent.value.state, sent.value.effects.first,
                                      reason: "unreachable", processors:)
failed.ok? # => true
```

Once the chart has stopped the report is refused with `:not_running`, and while
a round budget has halted it with `:halted`; nothing is written, and the miss is
the host's to record.

An `<invoke>` of the SCXML type runs in process: the driver compiles the
`<content>` markup and starts it as a child session on the parent's virtual
clock, its session id the parent's, a dot and the invoke id. `src` is never
fetched, and an invoke of any other type raises `error.execution` inside the
chart.

## Position export and import

A position is where an execution stands, written as plain data in the
reference's string-id vocabulary: a Hash with String keys, whose values are
Strings, Integers, booleans, and Arrays and Hashes of them. A host stores it as
JSON, and imports it into a machine, which may be a fresh compile of the same
source, to continue from there. Every datamodel value in it is text in
predicator's tagged-value encoding, so a date, a duration or an undefined value
survives JSON:

```ruby
position = Statifier.export_position(counted.value.state).value
position["configuration"] # => ["a"]
position["datamodel"]["count"] # => "1"

require "json"

stored = JSON.generate(position)
restored = Statifier.import_position(Statifier.compile(source).value, JSON.parse(stored), processors: {})
restored.ok? # => true

# The restored execution steps as the original does
from_original = Statifier.step(counted.value.state, "e.inc")
from_restored = Statifier.step(restored.value, "e.inc")
Statifier.export_position(from_restored.value.state).value == Statifier.export_position(from_original.value.state).value # => true
```

A position holds what the interpreter holds between two calls and nothing of
the driver's own: no pending timer, no queued external event, no send a
processor holds, no virtual time and no donedata. An import starts those as a
fresh start does, so a host that needs a timer keeps it itself. An export is
refused with a `Statifier::Position::Refusal` (`:internal_queue_not_empty`,
`:unnameable_states` or `:unencodable_value`) and an import with
`:malformed_export` or `:unknown_state_ids`:

```ruby
Statifier.import_position(machine, {}).error.reason # => :malformed_export
```

The round trip is proved over the conformance corpus, not only by the example
above: the test suite takes a point after the start and after every step of
each scion case, exports the position there, carries it through JSON, imports
it into a fresh compile and drives the remaining steps, requiring the imported
execution to agree with the unbroken one at every later step
(`test/conformance/position_property.rb`).

## Compatibility

- **Ruby 3.3 and later.** `required_ruby_version` in the gemspec is
  `>= 3.3`, and CI runs the test suite on Ruby 3.3, 3.4 and 4.0.
- **One runtime dependency**, `predicator` (`>= 2.0`, `< 3`). The XML front
  end is hand-written, so no XML gem is needed.
- **No shared mutable state.** The machine and the state are immutable
  values, there is no global configuration, and nothing is kept between calls
  but the state a call answers. Processors and the clock are passed with each
  call, so several executions can run side by side.

## Conformance

The gem is held to the conformance corpus of statifier-ex, vendored under
`conformance/statifier/` at the tag `v2.16.0` (commit
`76742af12138887c7f95125a80edf2b0a7dbaaf3`, corpus hash
`sha256:7440f9a34a84b0657cb3bde11f96cf1707db08fb05e202c1e0249ab965517cc8`,
recorded in `conformance/statifier.vendored.json`). The corpus is the arbiter:
a case this package answers differently from the corpus is this package's bug,
and no case is skipped. `conformance/registry.json` lists the cases this gem
claims to pass, and the gate fails if one of them does not.

| Claim | Cases claimed | Of |
|---|---|---|
| `scion` | 119 | 119 cases in the scion suite |
| `statifier` | 22 | 36 cases in the statifier suite |
| `w3c-mandatory` | 152 | 154 mandatory cases in the w3c suite |
| `w3c-optional` | 2 | 14 optional cases in the w3c suite |

The registry holds 295 entries, which is the sum of the four rows. A claim is
the set of its entries, not a statement that every case of its suite passes.

What is not claimed yet:

- `w3c/test330` and `w3c/test552`, the two mandatory w3c cases the run fails,
  the reference's registry does not claim them either.
- Twelve optional w3c cases whose host needs the Basic HTTP Event I/O
  Processor, which this package does not provide.
- Fourteen cases of the `statifier` suite, the reference's own: the ten diff
  cases, whose host keys the conformance runner does not read yet; and the four
  cases that state an exported position, which it does not compare yet.

Running the gate prints the gap list: every unclaimed case with the features it
needs and whether it passes or why it fails.

## Documentation

- Look up
  - Every public method and class carries a YARD doc comment in `lib/`:
    the `Statifier` module's eight calls and `Statifier::Result`, the driver's
    values (`Statifier::Driver::Moved` and `DoneStatus`), `Statifier::Effect`,
    `Statifier::Event` and `Statifier::Position`.
  - [The changelog](CHANGELOG.md): what changed in each version.
  - [The conformance apparatus](conformance/README.md): what is vendored, from
    where, and how the check, the runner and the ratchet work.
- Understand
  - [The reference implementation](https://github.com/riddler/statifier-ex),
    whose records decide the statechart semantics this gem implements.

## Development

```bash
mise install                          # the Ruby that mise.toml pins
mise exec -- bundle install           # the dev tools
mise exec -- bundle exec rake         # the gate: rubocop, corpus:check, registry, then the tests
```

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/riddler/statifier-rb.

## License

MIT; see `LICENSE`.

<!-- BADGES -->
[badge_license_url]: https://img.shields.io/badge/license-MIT-brightgreen.svg?cacheSeconds=3600?style=flat-square
[badge_ci_url]: https://github.com/riddler/statifier-rb/actions/workflows/ci.yml/badge.svg
