# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

Atelier is an Elixir-based multi-agent code generation system. It uses a team of specialized agents communicating via Phoenix.PubSub to generate, validate, audit, and commit code automatically. The system integrates with LLMs (Ollama or Anthropic) for code generation and uses a Rust NIF for code scanning. Includes an optional Phoenix LiveView dashboard for real-time monitoring.

## Build & Development Commands

```bash
# Compile the project (includes Rust NIF compilation via Rustler)
mix compile

# Run interactive shell with project loaded
iex -S mix

# Run tests
mix test

# Run a single test file
mix test test/atelier_test.exs

# Run linting
mix credo

# Format code
mix format

# Build dashboard assets
mix assets.build

# Start with dashboard on localhost:4000
# Set config :atelier, start_dashboard: true in config.exs, or:
AtelierWeb.Endpoint.start_link([])
```

## Testing Locally

Requires `ollama` running locally (default endpoint: `http://localhost:11434`).

```elixir
# In iex -S mix:
Atelier.Studio.start_project("my-project")
Atelier.Studio.request_feature("my-project", "A shopping cart module")
```

Generated files are written to `/tmp/atelier_studio/{project_id}/`.

## Architecture

### Core Components

- **`Atelier.Studio`** - Entry point. Starts agent teams and routes feature requests to the Architect.
- **`Atelier.Agent`** - GenServer delegator that routes messages to role-specific implementation modules based on the `:role` option.
- **`Atelier.LLM`** - Abstraction over LLM providers (`:ollama` or `:anthropic`). Includes `clean_code/1` for stripping markdown from LLM responses.
- **`Atelier.Storage`** - File I/O for project workspaces under `/tmp/atelier_studio/`.
- **`Atelier.Native.Scanner`** - Rust NIF (via Rustler) for scanning code for forbidden patterns.

### Agent System

Agents are spawned via `DynamicSupervisor` and communicate through `Phoenix.PubSub` on topic `"project:{project_id}"`. Each agent implements `Atelier.Agent.Worker` behaviour with `init_state/1`.

**Agent roles and responsibilities:**
- **Architect** - Receives requirements, produces JSON blueprint of files to generate
- **Writer** - Generates code from blueprints, handles validation failures with retry logic (max 3 attempts)
- **Validator** - Syntax checks generated code (supports .js, .ex, .py)
- **Auditor** - Scans code for forbidden patterns via Rust NIF, suggests LLM-based fixes
- **Runner** - Executes validated code files
- **GitBot** - Auto-commits validated files
- **Clerk** - Tracks project progress, writes MANIFEST.md
- **Analyst** - Collects failures, generates LESSONS_LEARNED.md post-mortem
- **Researcher** - Performs web searches for the Architect using DuckDuckGo API
- **Environment** - Health checks for LLM infrastructure

### Message Flow

1. `Studio.request_feature` → Architect receives `{:design_spec, requirement}`
2. Architect broadcasts `{:blueprint_ready, files}` 
3. Writer processes files sequentially, broadcasts `{:code_ready, code, filename}`
4. Validator and Auditor react to `:code_ready`
5. On `{:validation_passed, filename}`, Clerk broadcasts `{:file_validated, filename}`
6. GitBot and Runner react to `:file_validated`
7. On failures, Writer receives `{:validation_failed, ...}` or `{:execution_failure, ...}` and retries

### Supervision Tree

```
Atelier.Supervisor
├── Phoenix.PubSub (Atelier.PubSub)
├── DynamicSupervisor (Atelier.AgentSupervisor) - spawns Agent processes
├── Task.Supervisor (Atelier.LLMTaskSupervisor) - async LLM calls
├── Atelier.Dashboard.EventCollector - collects events for dashboard
└── AtelierWeb.Endpoint (optional) - LiveView dashboard on port 4000
```

## Configuration

In `config/config.exs`:
- `llm_provider`: `:ollama` (default) or `:anthropic`
- `ollama_model`: Model name (default: `"llama3"`)
- `ollama_endpoint`: Ollama API URL (default: `"http://localhost:11434"`)
- `llm_timeout`: Request timeout in ms (default: `120_000`)
- `start_dashboard`: Auto-start LiveView dashboard (default: `false`)
- For Anthropic: set `ANTHROPIC_API_KEY` environment variable

## Rust NIF

Located in `native/atelier_native_scanner/`. Compiled automatically by Rustler during `mix compile`. The NIF provides `scan_code/2` which checks code for forbidden strings.
