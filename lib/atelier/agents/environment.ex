defmodule Atelier.Agents.Environment do
  @moduledoc """
  Environment agent responsible for health checking LLM and Sprites infrastructure.
  """

  require Logger

  alias Atelier.Storage

  @behaviour Atelier.Agent.Worker

  @spec init_state(Keyword.t()) :: map()
  def init_state(opts) do
    %{
      role: :environment,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}"
    }
  end

  @spec handle_cast(term(), map()) :: {:noreply, map()}
  def handle_cast(:check_health, state) do
    provider = Application.get_env(:atelier, :llm_provider)
    Logger.info("🌍 Checking health for provider: #{provider}")

    with :ok <- check_provider(provider),
         :ok <- check_sprites(state.project_id) do
      Logger.info("✅ Infrastructure is healthy.")
      Phoenix.PubSub.broadcast(Atelier.PubSub, state.topic, :infra_ready)
    else
      {:error, reason} ->
        Logger.error("❌ Infrastructure check failed: #{reason}")
        Phoenix.PubSub.broadcast(Atelier.PubSub, state.topic, {:infra_error, reason})
    end

    {:noreply, state}
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  defp check_provider(:ollama) do
    endpoint = Application.get_env(:atelier, :ollama_endpoint, "http://localhost:11434")

    case Req.get("#{endpoint}/api/tags") do
      {:ok, %{status: 200}} -> :ok
      _ -> {:error, "Ollama unreachable at #{endpoint}"}
    end
  end

  defp check_provider(:anthropic) do
    api_key = Application.get_env(:atelier, :anthropic_api_key)

    if api_key && String.length(api_key) > 0 do
      :ok
    else
      {:error, "Anthropic API Key is missing or empty"}
    end
  end

  # Check Sprites connectivity if enabled
  defp check_sprites(project_id) do
    if Storage.sprites_enabled?() do
      Logger.info("👻 Checking Sprites.dev connectivity...")
      sprite_name = "atelier-#{project_id}"

      case Storage.sprites_client() do
        nil ->
          {:error, "Sprites enabled but SPRITES_TOKEN not configured"}

        client ->
          # Try to create or verify the sprite exists
          case Sprites.create(client, sprite_name) do
            {:ok, _} ->
              Logger.info("✅ Sprites.dev connection verified", sprite: sprite_name)
              :ok

            {:error, reason} ->
              {:error, "Sprites.dev connection failed: #{inspect(reason)}"}
          end
      end
    else
      # Sprites not enabled, skip check
      :ok
    end
  end

  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info(_msg, state), do: {:noreply, state}
end
