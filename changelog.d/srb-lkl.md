### Added

* `Statifier.start(machine, **options)` starts a compiled chart and answers a result whose `value` is the chart's state, an immutable value, and the effects the start made; the options are `session_id:` (minted as `sess_` and 26 base32 symbols when absent), `datamodel:`, `processors:`, `max_macrostep_rounds:`, `trace:` and `clock:`.
* `Statifier.step(state, name, data:)` sends the chart one external event and runs it to a stable configuration; it answers the error `:not_running` once the chart has stopped.
* `Statifier.advance(state, milliseconds)` moves the chart's virtual clock forward and fires every delayed send due by then, earliest first; it answers the error `:invalid_duration` for a negative or non-finite duration.
* `Statifier.configuration(state)` answers the active states by id, and `Statifier.done?(state)` whether the chart has stopped, with its donedata and the states it stopped in.
* A send of a type a host registers is handed to the host's processor for that type, passed with every call: its `deliver(send, event, context)`, its `cancel(cancel, context)` for a delayed send it holds, and its `ioprocessors_entry(type, context)` for `_ioprocessors`.
* A host reads the validator's warnings on the compiled machine, `machine.warnings`.
