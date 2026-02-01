import Config

# Configure the Elixir Logger
config :logger, :console,
  # This format string includes $metadata to show your [:role, :project]
  format: "$time $metadata[$level] $message\n",
  # Tells Logger which specific metadata keys to pull from the process
  metadata: [
    :role,
    :project,
    :project_id,
    :path,
    :filename,
    :content_size,
    :provider,
    :input_length,
    :response_length,
    :message_type,
    :code_length,
    :issue_count,
    :issues,
    :suggestion_length,
    :error,
    :reason,
    :output,
    :status,
    :project_path,
    :extension,
    :exit_code,
    :message,
    :add_status,
    :add_output,
    :commit_status,
    :commit_output,
    :model,
    :agent_count,
    :requirement_length
  ],
  colors: [enabled: true, info: :green, debug: :cyan, error: :red]

# Default Agent settings
config :atelier,
  llm_provider: :ollama,
  ollama_model: "llama3"

# Import environment specific config (optional but standard)
# import_config "#{config_env()}.exs"
