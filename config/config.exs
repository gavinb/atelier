import Config

# Configure the Elixir Logger
config :logger, :console,
  level: :info,
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
  ollama_model: "llama3",
  ollama_endpoint: "http://localhost:11434",
  llm_timeout: 120_000,
  # Set to true to auto-start the dashboard, or start manually with:
  # AtelierWeb.Endpoint.start_link([])
  start_dashboard: false

# Dashboard configuration
config :atelier, AtelierWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  secret_key_base: "atelier_dashboard_secret_key_base_change_in_production_abcdef",
  live_view: [signing_salt: "atelier_lv_salt"],
  render_errors: [formats: [html: AtelierWeb.ErrorHTML], layout: false],
  pubsub_server: Atelier.PubSub

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  atelier: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  atelier: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config (optional but standard)
# import_config "#{config_env()}.exs"
