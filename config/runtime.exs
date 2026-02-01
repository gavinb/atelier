import Config

if config_env() == :dev do
  config :atelier,
    ollama_endpoint: System.get_env("OLLAMA_URL") || "http://localhost:11434"
end

# If you decide to add a cloud provider later:
if config_env() == :prod do
  config :atelier,
    llm_provider: :anthropic,
    anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")
end
