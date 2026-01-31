import Config

# Default to local development
config :atelier,
  llm_provider: :ollama,
  ollama_model: "llama3"

config :logger, :console,
  format: "\n$time [$level] $message\n",
  # You can add custom metadata here
  metadata: [:pid, :role]

# You can override this in a config/runtime.exs later for production
