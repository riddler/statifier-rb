# Statifier

The interpreter core of an SCXML statechart engine, for Ruby.

This branch of the repository is the 0.1.0 rewrite in progress. It replaces the
0.0.1 stub published in 2019, which carried no statechart code. The `Statifier`
module is empty today; the interpreter, the conformance corpus and the full
README arrive in later changes.

## Development

```bash
mise install                          # the Ruby that mise.toml pins
mise exec -- bundle install           # the dev tools
mise exec -- bundle exec rake         # the gate: rubocop, then the tests under SimpleCov
```

## License

MIT; see `LICENSE`.
