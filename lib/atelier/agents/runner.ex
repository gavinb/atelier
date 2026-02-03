defmodule Atelier.Agents.Runner do
  @moduledoc """
  Runner agent responsible for executing validated code files.

  Supports two execution modes:
  - Local: Runs code directly on the host machine (default)
  - Sprites: Runs code in an isolated sandbox via sprites.dev

  Set `config :atelier, :sprites, enabled: true` to use sandboxed execution.
  """

  require Logger

  alias Atelier.Storage

  @behaviour Atelier.Agent.Worker

  @spec init_state(Keyword.t()) :: map()
  def init_state(opts) do
    %{
      role: :runner,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}",
      sandbox: Storage.sprites_enabled?()
    }
  end

  @spec handle_cast(term(), map()) :: {:noreply, map()}
  def handle_cast(_msg, state), do: {:noreply, state}

  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info({:file_validated, filename}, state) do
    Logger.info("[Runner] Attempting to execute #{filename}...",
      sandbox: state.sandbox,
      project_id: state.project_id
    )

    # Determine how to run based on extension
    case Path.extname(filename) do
      ".js" -> execute("node", filename, state)
      ".ex" -> execute("elixir", filename, state)
      ".py" -> execute("python3", filename, state)
      _ -> Logger.debug("[Runner] No execution strategy for #{filename}")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Execute using Sprites sandbox
  defp execute(runtime, filename, %{sandbox: true} = state) do
    case Storage.get_sprite(state.project_id) do
      nil ->
        Logger.error("[Runner] Sprites not configured")
        broadcast_failure(filename, "Sprites not configured", state)

      sprite ->
        {output, exit_code} = Sprites.cmd(sprite, runtime, [filename], dir: "/workspace")

        if exit_code == 0 do
          Logger.info("[Runner] Sandbox execution successful", output: output)
          broadcast_success(filename, output, state)
        else
          Logger.error("[Runner] Sandbox execution failed", output: output, exit_code: exit_code)
          broadcast_failure(filename, output, state)
        end
    end
  end

  # Execute locally (original behavior)
  defp execute(runtime, filename, %{sandbox: false} = state) do
    project_path = Path.expand("/tmp/atelier_studio/#{state.project_id}")
    full_path = Path.join(project_path, filename)

    case System.cmd(runtime, [full_path], env: [], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("[Runner] Local execution successful", output: output)
        broadcast_success(filename, output, state)

      {output, _status} ->
        Logger.error("[Runner] Local execution failed", output: output)
        broadcast_failure(filename, output, state)
    end
  end

  defp broadcast_success(filename, output, state) do
    Phoenix.PubSub.broadcast(
      Atelier.PubSub,
      state.topic,
      {:execution_success, filename, output}
    )
  end

  defp broadcast_failure(filename, output, state) do
    Phoenix.PubSub.broadcast(
      Atelier.PubSub,
      state.topic,
      {:execution_failure, filename, output}
    )
  end
end
