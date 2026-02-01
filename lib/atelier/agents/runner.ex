defmodule Atelier.Agents.Runner do
  @moduledoc """
  Runner agent responsible for executing validated code files.

  Supports two execution modes:
  - Local: Runs code directly on the host machine (default)
  - Sprites: Runs code in an isolated sandbox via sprites.dev

  Set `config :atelier, Atelier.Sprites, enabled: true` to use sandboxed execution.
  """

  require Logger

  alias Atelier.Sprites

  @behaviour Atelier.Agent.Worker

  @spec init_state(Keyword.t()) :: map()
  def init_state(opts) do
    %{
      role: :runner,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}",
      sandbox: Sprites.enabled?()
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
    sprite_name = "atelier-#{state.project_id}"
    command = "cd /workspace && #{runtime} #{filename}"

    case Sprites.exec(sprite_name, command) do
      {:ok, output} ->
        Logger.info("[Runner] Sandbox execution successful", output: output)
        broadcast_success(filename, output, state)

      {:error, {:execution_failed, _code, output}} ->
        Logger.error("[Runner] Sandbox execution failed", output: output)
        broadcast_failure(filename, output, state)

      {:error, reason} ->
        Logger.error("[Runner] Sandbox error", error: inspect(reason))
        broadcast_failure(filename, "Sandbox error: #{inspect(reason)}", state)
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
