# Atelier

Atelier is an Elixir-based multi-agent code generation system. It uses a team of specialized AI agents communicating via Phoenix.PubSub to automatically generate, validate, audit, and commit code. The system integrates with LLMs (Ollama or Anthropic) and includes a Rust NIF for code scanning.

## Features

- **Multi-agent architecture** - Specialized agents for design, writing, validation, auditing, and git operations
- **Automatic retry logic** - Writer agent retries failed validations up to 3 times with LLM-assisted fixes
- **Syntax validation** - Supports JavaScript, Elixir, and Python files
- **Code auditing** - Rust NIF scans for forbidden patterns (TODO, FIXME, etc.)
- **Auto-commit** - GitBot automatically commits validated files with LLM-generated commit messages
- **Post-mortem analysis** - Analyst agent generates LESSONS_LEARNED.md for failed builds

## Requirements

- Elixir 1.18+
- Rust (for NIF compilation)
- [Ollama](https://ollama.ai/) running locally (default), or Anthropic API key

## Installation

```bash
# Clone the repository
git clone <repo-url>
cd atelier

# Install dependencies (compiles Rust NIF automatically)
mix deps.get
mix compile
```

## Configuration

Edit `config/config.exs` to change LLM settings:

```elixir
config :atelier,
  llm_provider: :ollama,      # or :anthropic
  ollama_model: "llama3"      # model name for Ollama
```

For Anthropic, set the `ANTHROPIC_API_KEY` environment variable.

## Usage

### Interactive (IEx)

```bash
iex -S mix
```

```elixir
# Start a project (spawns all agents)
Atelier.Studio.start_project("my-project")

# Request a feature
Atelier.Studio.request_feature("my-project", "A shopping cart module with add/remove functions")

# Enable debug logging for more detail
Logger.configure(level: :debug)
```

### Command Line

```bash
mix atelier.run "A REST API for managing todos"
```

### Output

Generated files are written to `/tmp/atelier_studio/{project_id}/`, including:
- Generated source files
- `MANIFEST.md` - Project progress and status
- `LESSONS_LEARNED.md` - Post-mortem analysis (if failures occurred)

## Architecture

### Agent Roles

| Agent | Responsibility |
|-------|---------------|
| **Architect** | Receives requirements, produces JSON blueprint of files to generate |
| **Writer** | Generates code from blueprints, handles validation failures with retry logic |
| **Validator** | Syntax checks generated code (.js, .ex, .py) |
| **Auditor** | Scans code for forbidden patterns via Rust NIF, suggests fixes |
| **Runner** | Executes validated code files |
| **GitBot** | Auto-commits validated files with LLM-generated messages |
| **Clerk** | Tracks project progress, writes MANIFEST.md |
| **Analyst** | Collects failures, generates LESSONS_LEARNED.md |
| **Researcher** | Web search for Architect (currently stubbed) |
| **Environment** | Health checks for LLM infrastructure |

### Message Flow

```
Studio.request_feature
       ↓
   Architect → {:blueprint_ready, files}
       ↓
    Writer → {:code_ready, code, filename}
       ↓
  Validator ────────────────────┐
       ↓                        ↓
{:validation_passed}    {:validation_failed}
       ↓                        ↓
    Clerk                   Writer (retry)
       ↓
{:file_validated}
       ↓
  GitBot + Runner
       ↓
:project_finished
```

## Development

```bash
# Run tests
mix test

# Run linter
mix credo

# Format code
mix format

# Export source (excludes build artifacts)
mix export
```

## Known Issues

- **Researcher agent is stubbed** - Web search returns hardcoded responses
- **No LLM timeout handling** - Slow/unresponsive LLM calls may hang indefinitely
- **Agents don't terminate** - After `:project_finished`, agent processes remain running

## License

MIT
