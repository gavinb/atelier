defmodule Atelier.Agents.Environment do
  @moduledoc """
  Environment agent responsible for health checking LLM infrastructure.
  """

  require Logger

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

    case check_provider(provider) do
      :ok ->
        Logger.info("✅ Infrastructure is healthy.")
        Phoenix.PubSub.broadcast(Atelier.PubSub, state.topic, :infra_ready)

      {:error, reason} ->
        Logger.error("❌ Infrastructure check failed: #{reason}")
        Phoenix.PubSub.broadcast(Atelier.PubSub, state.topic, {:infra_error, reason})
    end

    {:noreply, state}
  end

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
      # A simple 'headers only' or dummy request to verify the key
      :ok
    else
      {:error, "Anthropic API Key is missing or empty"}
    end
  end

  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info(_msg, state), do: {:noreply, state}
end
