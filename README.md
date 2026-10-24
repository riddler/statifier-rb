# Statifier

The interpreter core of an SCXML statechart engine, for Ruby.

This branch of the repository is the 0.1.0 rewrite in progress. It replaces the
0.0.1 stub published in 2019, which carried no statechart code. Today the
`Statifier` module compiles a chart, `Statifier.compile(source)`, into a frozen
machine, and its driver steps one: `Statifier.start(machine)`,
`Statifier.step(state, "e.go")` and `Statifier.advance(state, 10)` each answer
a result whose value is the new state and the effects, and
`Statifier.configuration(state)` and `Statifier.done?(state)` read a state.
The full README arrives in a later change. The conformance corpus this
package is checked against is vendored under `conformance/`, whose README says
what is copied and from where; no case is claimed in its registry yet.

## Development

```bash
mise install                          # the Ruby that mise.toml pins
mise exec -- bundle install           # the dev tools
mise exec -- bundle exec rake         # the gate: rubocop, corpus:check, registry, then the tests
```

## License

MIT; see `LICENSE`.
