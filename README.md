# Statifier

The interpreter core of an SCXML statechart engine, for Ruby.

This branch of the repository is the 0.1.0 rewrite in progress. It replaces the
0.0.1 stub published in 2019, which carried no statechart code. Today the
`Statifier` module compiles a chart, `Statifier.compile(source)`, into a frozen
machine; the interpreter that steps it and the full README arrive in later
changes. The conformance corpus this package is checked against is vendored
under `conformance/`, whose README says what is copied and from where.

## Development

```bash
mise install                          # the Ruby that mise.toml pins
mise exec -- bundle install           # the dev tools
mise exec -- bundle exec rake         # the gate: rubocop, corpus:check, registry, then the tests
```

## License

MIT; see `LICENSE`.
