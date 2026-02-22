# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-02-22

### Added
- Multi-agent code generation system with 10 specialized agents
- Architect, Writer, Validator, Auditor, Runner, GitBot, Clerk, Analyst, Researcher, Environment
- Phoenix.PubSub-based agent communication
- LLM integration with Ollama and Anthropic providers
- Rust NIF for code scanning via Rustler
- Syntax validation for JavaScript, Elixir, and Python
- Automatic retry logic with LLM-assisted fixes (up to 3 attempts)
- Git auto-commit with LLM-generated commit messages
- Post-mortem analysis with LESSONS_LEARNED.md generation
- Sandboxed code execution via Sprites.dev
- Optional Phoenix LiveView dashboard for real-time monitoring
- `mix atelier.run` task for command-line usage
- Web search capability via DuckDuckGo API
