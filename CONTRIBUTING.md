# Contributing to Atelier

Thanks for your interest in contributing!

## Getting Started

1. Fork the repository
2. Clone your fork and set up the project:

```bash
git clone https://github.com/your-username/atelier.git
cd atelier
cp .env.example .env
mix deps.get
mix compile
```

3. Make sure tests pass: `mix test`

## Development

```bash
mix test          # Run tests
mix credo         # Run linter
mix format        # Format code
mix format --check-formatted  # Check formatting (CI uses this)
```

## Submitting Changes

1. Create a feature branch: `git checkout -b my-feature`
2. Make your changes
3. Ensure `mix test`, `mix credo`, and `mix format --check-formatted` all pass
4. Commit with a descriptive message
5. Open a pull request

## Reporting Issues

Please include:
- Elixir/Erlang version (`elixir --version`)
- Steps to reproduce
- Expected vs actual behavior
- Any relevant log output
