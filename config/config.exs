import Config

# Default to local development
config :atelier,
  llm_provider: :ollama,
  ollama_model: "llama3"

# You can override this in a config/runtime.exs later for production
