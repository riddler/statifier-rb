### Added

* `Statifier.compile(source)` compiles an SCXML document into a frozen machine and answers a result: `ok?`, the machine as `value`, or as `error` the list of refusals from the first stage that refused (the XML reader, the lowering, the validator, or an expression predicator refuses). A validator warning never refuses; the machine carries it.
