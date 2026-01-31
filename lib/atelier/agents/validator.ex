defmodule Atelier.Agents.Validator do
  @moduledoc """
  Validator agent responsible for syntax validation of generated code.
  """

  alias Phoenix.PubSub

  def handle_cast(_msg, state), do: {:noreply, state}

  def handle_info({:code_ready, _code, filename}, state) do
    IO.puts("🧪 Validator: Checking syntax for #{filename}...")

    full_path = Path.expand("tmp/atelier_studio/#{state.project_id}/#{filename}")

    # Determine the check command based on extension
    result =
      case Path.extname(filename) do
        ".js" -> System.cmd("node", ["--check", full_path])
        ".ex" -> System.cmd("elixirc", [full_path, "-o", "tmp/atelier_studio/build"])
        ".py" -> System.cmd("python3", ["-m", "py_compile", full_path])
        _ -> {:ok, "No validator for this file type"}
      end

    case result do
      {_output, 0} ->
        IO.puts("✅ Validator: #{filename} syntax is valid.")
        PubSub.broadcast(Atelier.PubSub, state.topic, {:validation_passed, filename})

      {error_msg, _exit_code} ->
        IO.puts("❌ Validator: #{filename} has syntax errors!")
        PubSub.broadcast(Atelier.PubSub, state.topic, {:validation_failed, filename, error_msg})
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
