# Atelier

Atelier is an Elixir-based multi-agent code generation system. It uses a team of specialized AI agents communicating via Phoenix.PubSub to automatically generate, validate, audit, and commit code. The system integrates with LLMs (Ollama or Anthropic) and includes a Rust NIF for code scanning.

## Features

- **Multi-agent architecture** - Specialized agents for design, writing, validation, auditing, and git operations
- **Automatic retry logic** - Writer agent retries failed validations up to 3 times with LLM-assisted fixes
- **Syntax validation** - Supports JavaScript, Elixir, and Python files
- **Code auditing** - Use a Rust NIF to scan for forbidden patterns (TODO, FIXME, etc.)
- **Auto-commit** - GitBot automatically commits validated files with LLM-generated commit messages
- **Post-mortem analysis** - Analyst agent generates LESSONS_LEARNED.md for failed builds
- **Live Dashboard** - Optional Phoenix LiveView dashboard for real-time project monitoring
- **Runs locally** - Can run using local Ollama models with the LiteLLM service
- **Execute in Sandbox** - (WIP feature) Runs the generated code in a Sprites.dev sandbox

## Requirements

- Elixir 1.18+
- Rust (for NIF compilation)
- [Ollama](https://ollama.ai/) running locally (default), or Anthropic API key

## Installation

```bash
# Clone the repository
git clone https://github.com/gavinb/atelier.git
cd atelier

# Set up environment variables
cp .env.example .env
# Edit .env with your tokens (see Configuration below)

# Install dependencies (compiles Rust NIF automatically)
mix deps.get
mix compile
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and fill in the values you need:

| Variable | Required | Description |
|----------|----------|-------------|
| `SPRITES_TOKEN` | For sandboxed execution | Get one at [sprites.dev](https://sprites.dev) or via `sprite login` |
| `ANTHROPIC_API_KEY` | For Anthropic provider | From [console.anthropic.com](https://console.anthropic.com) |
| `OLLAMA_URL` | No | Ollama endpoint (default: `http://localhost:11434`) |

### LLM Provider

Edit `config/config.exs` to change LLM settings:

```elixir
config :atelier,
  llm_provider: :ollama,        # or :anthropic
  ollama_model: "llama3",       # model name for Ollama
  ollama_endpoint: "http://localhost:11434",  # Ollama API endpoint
  llm_timeout: 120_000          # LLM request timeout in ms (default: 2 minutes)
```

### Sandboxed Execution (Sprites)

By default, Atelier runs generated code in isolated [Sprites.dev](https://sprites.dev) sandboxes. To disable sandboxing and run locally instead, set in `config/config.exs`:

```elixir
config :atelier, :sprites, enabled: false
```

## Architecture

The Elixir language and BEAM runtime provide first-class support for orchestrating
multiple agents and LLMs. Each Atelier Agent is an independently GenServer process,
passing messages between different roles and collaborating to achieve the stated goal.

### Local LLMs

The simplest usage model is to configure your Anthropic API Key for Claude and run
the models in the cloud. However, it is possible to use your own local LLMs if
suitably configured.

A very efficient multi-node solution is a DeskPi CM5 cluster board, which features
up to six RaspberryPi Compute Module 5 boards. With sufficient RAM, these can run
LiteLLM with Ollama and various models to support the different agent roles.

### Closing the Loop

LLMs often make mistakes, yet do not actively learn from them. This project is designed
to not only solve the problem, but learn from mistakes. Each session is reviwed and
a "lessons learned" file is recorded. The plan is that eventually these can be built
into a RAG forming a knowledgebase of problems and solutions, so that future agents
don't have to solve the same problem from scratch each time. (WIP)

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

Atelier can be run completely from the command line, running multiple concurrent agents,
showing outputs

```bash
mix atelier.run "A REST API for managing todos"
```

### Output

Generated files are written to `/tmp/atelier_studio/{project_id}/`, including:

- Generated source files
- `MANIFEST.md` - Project progress and status
- `LESSONS_LEARNED.md` - Post-mortem analysis (if failures occurred)

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
| **Researcher** | Web search for Architect using DuckDuckGo API |
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

## Dashboard (Optional)

Atelier includes an optional Phoenix LiveView dashboard for monitoring projects in real-time.

### Starting the Dashboard

**Option 1: Auto-start**

Set in `config/config.exs`:
```elixir
config :atelier, start_dashboard: true
```

Then run:
```bash
iex -S mix
```

**Option 2: Manual start**

```elixir
# In IEx
AtelierWeb.Endpoint.start_link([])
```

The dashboard will be available at [http://localhost:4000](http://localhost:4000)

### Features

- **Project list** - See all active/completed projects
- **File progress** - Track files through the pipeline (pending → validating → committed)
- **Live event feed** - Real-time log of all agent messages
- **Project details** - Click a project to see its files and events

## Development

```bash
# Run tests
mix test

# Run linter
mix credo

# Format code
mix format

# Build dashboard assets
mix assets.build

# Export source (excludes build artifacts)
mix export
```

## License

[MIT](LICENSE)

# Design

# Sample Session

Once the project is compiled, a custom `mix` command can be used to
run the agents from the command line and build a project. A sample
session follows below:

```
% mix atelier.run "Create a typescript todo app server with a rest api"

21:24:00.923 [info] Initializing workspace
21:24:00.924 [debug] Initializing git repository
21:24:00.960 [debug] Git repository initialized

21:24:00.960 [info] Starting project
✨ Agent [environment] joined Atelier for cli-7

21:24:00.964 [debug] Starting agents
✨ Agent [architect] joined Atelier for cli-7
✨ Agent [writer] joined Atelier for cli-7
✨ Agent [auditor] joined Atelier for cli-7
✨ Agent [clerk] joined Atelier for cli-7
✨ Agent [validator] joined Atelier for cli-7
✨ Agent [git_bot] joined Atelier for cli-7
✨ Agent [runner] joined Atelier for cli-7
✨ Agent [analyst] joined Atelier for cli-7
✨ Agent [researcher] joined Atelier for cli-7

21:24:00.970 [info] 🌍 Checking health for provider: ollama
21:24:01.004 [info] ✅ Infrastructure is healthy.
🚀 Infra ready. Architecting...

📐 Architect: Designing system for: Create a typescript todo app server with a rest api
21:24:01.005 [debug] Sending design spec to architect
📐 Architect: Blueprint ready with 4 files.
✍️  Writer: Marching orders received. Processing 4 files sequentially...
✍️  Writer: Generating [todo-api.ts]...

🧪 Validator: Checking syntax for todo-api.ts...
🔍 Auditor: Running infra-scan...
✍️  Writer: Generating [models/todo.ts]...
✅ Validator: todo-api.ts syntax is valid.

📦 GitBot: todo-api.ts validated. Preparing commit...
21:24:48.529 [info] [Writer] Validation passed for todo-api.ts. Resetting retry counter.

21:24:48.529 [info] [Runner] Attempting to execute todo-api.ts...
21:24:48.529 [debug] [Runner] No execution strategy for todo-api.ts

✅ Auditor: Clean!
21:24:48.535 [debug] Requesting commit message from LLM
21:24:50.351 [debug] File written locally
✍️  Writer: Generating [services/todo.service.ts]...
🧪 Validator: Checking syntax for models/todo.ts...
🔍 Auditor: Running infra-scan...

✅ Validator: models/todo.ts syntax is valid.
✅ Auditor: Clean!

📦 GitBot: models/todo.ts validated. Preparing commit...
21:24:50.352 [info] [Writer] Validation passed for models/todo.ts. Resetting retry counter.
21:24:50.352 [info] [Runner] Attempting to execute models/todo.ts...
21:24:50.352 [debug] [Runner] No execution strategy for models/todo.ts

21:24:51.552 [debug] Running git add
21:24:51.606 [debug] Running git commit
🚀 GitBot: Committed todo-api.ts with message: ""Implemented API endpoint for retrieving all todos, accessible to public.""
🧪 Validator: Checking syntax for services/todo.service.ts...
✍️  Writer: Generating [server.ts]...
🔍 Auditor: Running infra-scan...
✅ Validator: services/todo.service.ts syntax is valid.
✅ Auditor: Clean!
📦 GitBot: services/todo.service.ts validated. Preparing commit...
🚀 GitBot: Committed models/todo.ts with message: "Add todo model interface definition."
🔍 Auditor: Running infra-scan...
🧪 Validator: Checking syntax for server.ts...
✍️  Writer: All tasks in blueprint completed.
✅ Auditor: Clean!
✅ Validator: server.ts syntax is valid.
📦 GitBot: server.ts validated. Preparing commit...
✅ Project completed successfully!
```
