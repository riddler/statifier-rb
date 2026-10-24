# Statifier

The interpreter core of an SCXML statechart engine, for Ruby.

This branch of the repository is the 0.1.0 rewrite in progress. It replaces the
0.0.1 stub published in 2019, which carried no statechart code. Today the
`Statifier` module compiles a chart, `Statifier.compile(source)`, into a frozen
machine, and its driver steps one: `Statifier.start(machine)`,
`Statifier.step(state, "e.go")` and `Statifier.advance(state, 10)` each answer
a result whose value is the new state and the effects, and
`Statifier.configuration(state)` and `Statifier.done?(state)` read a state.
`Statifier.export_position(state)` writes a state out as a position, plain data
ready for JSON in the reference's string-id vocabulary, and
`Statifier.import_position(machine, position)` reads one back in; a position
carries no pending timer, queued event or virtual time, so a host that needs
them keeps them itself. The full README arrives in a later change. The
conformance corpus this package is checked against is vendored under
`conformance/`, whose README says what is copied and from where; its registry
claims the scion suite.

## Development

```bash
mise install                          # the Ruby that mise.toml pins
mise exec -- bundle install           # the dev tools
mise exec -- bundle exec rake         # the gate: rubocop, corpus:check, registry, then the tests
```

## License

MIT; see `LICENSE`.
