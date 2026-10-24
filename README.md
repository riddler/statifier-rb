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
transition order (a state's own transitions before its children's). With `nil` for the declaration both lists are empty.

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
that refused the source: the XML reader, the lowering, the validator and the
compiler (when predicator refuses an expression). Their classes are internal.
Each refusal carries a `reason` symbol, a `message` for a person and a
`location`, the span of the source it names (`start_line`, `start_column`,
`start_offset`, `end_line`, `end_column` and `end_offset`); all but the
reader's carry a `detail` Hash too:

```ruby
Statifier.compile("<scxml>").error.first.reason # => :unclosed_element

unresolved = Statifier.compile(<<~SCXML)
  <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0">
    <state id="a"><transition event="e.go" target="zz"/></state>
  </scxml>
SCXML
unresolved.error.first.reason # => :unresolved_target

badcond = Statifier.compile(<<~SCXML)
  <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0">
    <state id="a"><transition event="e.go" cond="1 +" target="a"/></state>
  </scxml>
SCXML
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
`round` counters as they stood when it was made. Every effect the chart's
runs answered is among the call's effects, in the order made, whatever the
driver did with it:

| Effect | What the driver does | What the host does with it |
|---|---|---|
| `Send` of a type the host registered | hands it to that type's processor, `deliver` | delivers it, in its processor |
| `Send` of the SCXML type, or none | routes it by its `target`: to the chart's own external queue, its internal queue, its parent or a live child | reads it, if it wants a record |
| `SendDelayed` of a type the host registered | hands it to that type's processor, which holds it | schedules it, in its processor |
| `SendDelayed` of the SCXML type, or none | holds it as a pending timer until `advance` reaches it | learns of an event due later |
| a send of any other type | nothing: the chart refuses it with `error.execution`, and no effect is answered | nothing |
| `Cancel` | drops every pending timer under its `send_id`, and tells a processor holding a delayed send under it, once | learns that the delayed send is dropped |
| `Invoke`, `CancelInvoke`, `Autoforward` | runs an invocation of the SCXML type in process as a child session, stops it, or forwards an event to it; any other type raises `error.execution` | learns of an invocation the core starts, stops or forwards an event to |
| `Log` | nothing | records the label and the evaluated value |
| `DatamodelInit`, `DatamodelChange` | nothing | learns the datamodel as the chart starts, and each write after |
| `BudgetExhausted` | queues later external events without taking them; a fired timer to the chart itself joins its external queue, and any other is dropped | learns that a macrostep spent its round budget; the chart keeps running |
| `Done` | discards the pending timers and the queued external events | learns that the chart stopped, with the top-level final's donedata |
| `Child` | answers each effect an invoked child's execution answered, tagged with the child's `session_id`, a grandchild's with its own | reads the child's effects |

An error is never an effect: `error.execution` and `error.communication` are
events the chart takes from its internal queue, which a host sees in what the
chart does next, or as a `Trace::EventDequeued` effect for a chart started with
`trace: true`.

The `Trace` effects follow the interpreter step by step and are answered only
for a chart started with `trace: true`. An event is a `Statifier::Event`, the
one value every queue holds.

The surface is fixed: the ten calls, the values above and below, and, after
`require "statifier/basichttp"`, the Basic HTTP processor's. Every other
constant in the gem is private, and `test/surface_test.rb` lists the public
surface whole, failing on an addition or a removal. A value whose class is
private, such as the machine, a driver state or a compile refusal, is read by
its documented members.

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

## The Basic HTTP processor

The HTTP side of the gem is opt-in: `require "statifier/basichttp"` loads it,
and `require "statifier"` alone loads none of it and no HTTP library. It holds
the Basic HTTP Event I/O Processor of SCXML appendix C.2, the decoder for the
requests it sends, and the HTTP transport the processor makes its requests
through.

### Registering the processor

`Statifier::BasicHTTP::Processor.new` takes the address the host's own server
answers at (`base_url:`), a `report:` callable that takes each send the
processor could not deliver, and optionally a `transport:` (below; a
`NetHTTPTransport` when absent). Its `send_types` names it under the
processor's URI, `Statifier::BasicHTTP::EVENT_PROCESSOR`
(`http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor`), and under the short
form `basichttp`, so a chart may name either; pass them as `processors:` on
every call. A session's `_ioprocessors` then carries an entry under each, both
with the same `location`: the base URL, `/` and the session's id.

```ruby
require "statifier/basichttp"

misses = []
http = Statifier::BasicHTTP::Processor.new(base_url: "http://localhost:8080/scxml", report: misses.method(:<<))
processors = http.send_types

machine = Statifier.compile(<<~SCXML).value
  <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0">
    <state id="a">
      <onentry>
        <send event="e.go" type="basichttp" target="http://localhost:8080/scxml/s2">
          <param name="reply" expr="_ioprocessors['basichttp']['location']"/>
        </send>
      </onentry>
      <transition event="error.communication" target="failed"/>
    </state>
    <state id="failed"/>
  </scxml>
SCXML

moved = Statifier.start(machine, session_id: "s1", processors:).value
# The POST was made while the call ran; a miss is reported back after it returns
misses.each do |miss|
  moved = Statifier.report_send_failed(machine, moved.state, miss.effect, reason: miss.reason, processors:).value
end
```

### What a send becomes

Each send the processor is handed becomes one POST to its target, made once
through the transport while the call that handed it runs. The request is built
as the reference's processor builds it, by the shape of the send's data, with
one difference: names and keys always stand in byte order, which is the
reference's order for a map of 32 keys or fewer, while it lists a larger map in
an order of its own:

| The send's data | Body | Content type | The event name |
|---|---|---|---|
| a Hash (its `namelist` and `<param>` values) | each name and value as a form field, in byte order of the names | `application/x-www-form-urlencoded` | the form field `_scxmleventname`, first |
| none | the event name alone, as a form field | `application/x-www-form-urlencoded` | the form field `_scxmleventname` |
| any other value (a `<content>` body) | the value written as text | `text/plain` | `_scxmleventname` in the target's query string |

A send with no event name carries no `_scxmleventname`. A value is written as
text the same way wherever it goes:

| Value | Text |
|---|---|
| a String | as it is |
| `nil` | `null` |
| `Predicator::UNDEFINED` | the empty string |
| `true`, `false` | `true`, `false` |
| an Integer | its decimal digits |
| a Float | its shortest digits, as the reference spells them: `1.5`, `2.0`, `1.0e15`, `1.0e-7` |
| a list or a map | JSON text, `[1,2]` or `{"a":1}`, a map's members in byte order of their keys and `Predicator::UNDEFINED` inside as `null` |
| a date, a datetime, a duration, or a list or a map holding a value with no JSON form | predicator's tagged-value text, or the empty string when that encoder refuses the value |

Every request also carries the send's deduplication key in the
`scxml-send-key` header: the session's id, the send id, the macrostep, the
microstep, the round, the content index, the owner (`onentry.2.0`,
`transition.4`) and the ordinal, joined by `/`, the first two percent-encoded.
The same send carries the same key each time, so a receiver that deduplicates
on it takes each send once.

### When a send fails

A send with no target fails within the call that handed it, as appendix C.2.2
requires: the chart takes `error.communication` at the send's place and no
request is made. Any other miss is handed to `report:` as a
`Statifier::BasicHTTP::Failure` (its `session_id`, the send as `effect`, a
`reason` and a `detail`) before the processor returns, as the reference's
processor reports a miss to the sending session, which takes it after the step
it is in. The host
passes `effect` to `Statifier.report_send_failed` once the call has returned,
with the state that call answered:

| `reason` | When | `detail` |
|---|---|---|
| `:http_status` | the response's status is outside 2xx | the `Response` |
| `:transport_error` | the transport raised, or answered something other than a `Response` | the error |
| `:invalid_target` | the target is not a String | the target |
| `:no_timer` | the send has a delay | `nil` |

The processor holds no timer, so a delayed send is reported rather than held,
where the reference's processor holds it on a timer of its own.

### The receive side

`Statifier::BasicHTTP.decode` turns a request a host's own server took into the
event it carries, as the reference's decoder does; the gem runs no server. It
takes the method, the content type, the body, the query string and the
`scxml-send-key` header's value, and answers a `Statifier::Result` holding a
`Statifier::Event` or a `Statifier::BasicHTTP::Refusal`:

| Request | Event |
|---|---|
| a method other than POST | refused, `:method_not_allowed`: answer 405 with `Allow: POST` |
| a query string or body that does not decode to UTF-8 | refused, `:not_utf8`: answer 400 |
| an `scxml-send-key` that is not eight fields joined by `/` | refused, `:malformed_send_key`: answer 400 |
| a `_scxmleventname` field, in the query string or a form body | its first value, the query string's first, is the name |
| no `_scxmleventname` | the name is `HTTP.POST` |
| a form body | its other fields and the query string's are the data, a Hash, each value read as a `<content>` body's text is (`2` is the number 2), the last of a repeated name winning |
| a body of any other content type, JSON included | the body is the data, read the same way; the query string gives the name only |

The event's `origintype` is `EVENT_PROCESSOR`. A server resolves the request's
location to the session it holds, passes the event's `name` and `data` to
`Statifier.step`, and answers 204; deduplicating on the `scxml-send-key` value
is the server's. `Statifier.step` takes a name and data, so the chart reads no
`_event.origintype` for the event.

```ruby
decoded = Statifier::BasicHTTP.decode(method: "POST", content_type: "application/x-www-form-urlencoded",
                                      body: "_scxmleventname=e.go&n=2", query: nil)
decoded.value.name # => "e.go"
decoded.value.data # => {"n" => 2}
```

### The HTTP transport

A transport is anything that responds to `call`: a lambda, a method object or
an object. It takes one request and makes it, and either answers the response
that came back or raises the transport error:

- **The request**, `Statifier::BasicHTTP::Request`, a frozen value with
  `http_method` (an HTTP token such as `"POST"`), `url` (an absolute URL),
  `headers` (name and value pairs, in order, a name allowed more than once)
  and `body` (a String, already encoded, empty for none). Building one keeps
  a string that is already frozen and copies any other, and refuses a method or header name that is not an
  HTTP token and a header value holding a carriage return, a line feed or a
  NUL.
- **The response**, `Statifier::BasicHTTP::Response`, a frozen value with
  `status` (an Integer from 100 to 599), `headers` (name and value pairs) and
  `body` (a String, empty for none). Every status is a response: a status
  outside 2xx is answered, not raised.
- **The error**, `Statifier::BasicHTTP::TransportError`, the one error a
  transport raises when no response came back: a URL it cannot request, a
  connection refused or failed, a time bound passed, an exchange broken off.
  The error that caused it, when there was one, is its `cause`. One edge: a
  response the default transport reads but cannot build a `Response` from (a
  header name that is not an HTTP token, a header value holding a carriage
  return, a line feed or a NUL) is raised as a `TransportError` too, since no
  usable response came back.

A transport makes one attempt; retrying is not its job.

The default transport, `Statifier::BasicHTTP::NetHTTPTransport`, uses
Net::HTTP from the standard library (the `net-http` default gem), so it adds
no runtime dependency. Each call opens a connection of its own, verifies an
`https` peer as Net::HTTP does by default, and bounds each of opening the
connection, writing the request and reading the response by `timeout:`
seconds, five when absent. A host that needs other Net::HTTP settings (a
proxy, a certificate file) passes `connect:`, a callable that answers the
connection for a URL; `NetHTTPTransport.connection(uri, timeout:)` is the
default one, for a host's own to start from.

```ruby
require "statifier/basichttp"

request = Statifier::BasicHTTP::Request.new(
  http_method: "POST",
  url: "http://localhost:8080/s1",
  headers: [["content-type", "text/plain"]],
  body: "e.go"
)

# A host's own transport, here one that answers every request in memory
echo = ->(req) { Statifier::BasicHTTP::Response.new(status: 200, body: req.body) }
echo.call(request).body # => "e.go"

# The default transport
transport = Statifier::BasicHTTP::NetHTTPTransport.new(timeout: 2)
begin
  transport.call(request).status
rescue Statifier::BasicHTTP::TransportError => e
  e.message # why no response came back
end
```

## Compatibility

- **Ruby 3.3 and later.** `required_ruby_version` in the gemspec is
  `>= 3.3`, and CI runs the test suite on Ruby 3.3, 3.4 and 4.0.
- **One runtime dependency**, `predicator` (`>= 2.0`, `< 3`). The XML front
  end is hand-written, so no XML gem is needed, and the default HTTP
  transport uses Net::HTTP, a default gem.
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

| Suite | Claim | Cases | Claimed | Unclaimed |
|---|---|---|---|---|
| scion | `scion` | 119 | 119 | 0 |
| statifier | `statifier` | 36 | 36 | 0 |
| w3c | `w3c-mandatory` | 154 | 152 | 2 |
| w3c | `w3c-optional` | 14 | 13 | 1 |
| all | | 323 | 320 | 3 |

The registry holds 320 entries, which is the sum of the Claimed column. The
numbers are read from the registry and from the vendored corpus, not counted
by hand, and `test/conformance/readme_test.rb` fails when this section and
the registry disagree. A claim is the set of its entries, not a statement
that every case of its suite passes. The registry holds the same entries and
the same four claims as the reference's registry at that tag.

The optional w3c cases whose host needs the Basic HTTP Event I/O Processor
are driven through this gem's processor, delivering to an in-memory loopback
front in the test suite rather than to an HTTP server on a local port as the
reference's harness does: no socket is opened, so these cases prove the
processor and the core's event path, not a network round trip.

Three cases are not claimed, and the reference's registry does not claim any
of them either:

| Case | Claim | Why it is not claimed |
|---|---|---|
| `w3c/test201` | `w3c-optional` | The chart sends to itself over Basic HTTP and also sends its own timeout event; the chart's own event is taken before the delivered one, so it ends in `fail` |
| `w3c/test330` | `w3c-mandatory` | The guards compare `_event` fields against `undefined`, and a field the event does not carry (`sendid`, `origin`, `origintype`, `invokeid`, `data`) makes the comparison false, so it ends in `fail` |
| `w3c/test552` | `w3c-mandatory` | A `<data src>` is never fetched, so the datamodel value the case reads is never bound and it ends in `fail` |

Running the gate prints the gap list: every unclaimed case with the features it
needs and whether it passes or why it fails.

## Documentation

- Look up
  - Every public method and class carries a YARD doc comment in `lib/`:
    the `Statifier` module's ten calls, `Statifier::Result` and
    `Statifier::AcceptsCheck`, the driver's values (`Statifier::Driver::Moved`,
    `DoneStatus`, `Context` and `DeliveryFailure`), `Statifier::Effect`,
    `Statifier::Event` and `Statifier::Position`, and under
    `Statifier::BasicHTTP` the processor, its failure, the decoder and its
    refusal, and the HTTP transport's request, response, error and default
    transport.
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
