defmodule Atelier.Agents.Runner do
  require Logger

  def handle_info({:validation_passed, filename}, state) do
    # We only run files that look like "main" or entry points,
    # or perhaps we run everything for testing.
    Logger.info("[Runner] Attempting to execute #{filename}...")

    project_path = Path.expand("tmp/atelier_studio/#{state.project_id}")
    full_path = Path.join(project_path, filename)

    # Determine how to run based on extension
    case Path.extname(filename) do
      ".js" -> execute_command("node", [full_path], state)
      ".ex" -> execute_command("elixir", [full_path], state)
      ".py" -> execute_command("python3", [full_path], state)
      _ -> Logger.debug("[Runner] No execution strategy for #{filename}")
    end

    {:noreply, state}
  end

  defp execute_command(cmd, args, state) do
    # System.cmd returns {output, exit_status}
    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("[Runner] Execution Successful! Output:\n#{output}")
        Phoenix.PubSub.broadcast(Atelier.PubSub, state.topic, {:execution_success, filename, output})
      {output, _status} ->
        Logger.error("[Runner] Execution Failed! Output:\n#{output}")
        Phoenix.PubSub.broadcast(Atelier.PubSub, state.topic, {:execution_failure, filename, output})
    end
  end
end
