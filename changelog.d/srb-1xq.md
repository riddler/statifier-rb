### Added

* `Statifier.report_send_failed(machine, state, send, **options)` reports a send the host was handed and could not deliver: the chart takes `error.communication`, its `sendid` the send's id whether or not the author named it, and runs to a stable configuration; the options are `reason:` (not read), `processors:` and `clock:`. It answers the error `:not_running` once the chart has stopped and `:halted` while a round budget has halted it.
* A processor's `deliver` may answer `Statifier::Driver::DeliveryFailure.new(reason:)` for a send it cannot deliver, and the chart takes the same `error.communication` within the call that handed the send.
