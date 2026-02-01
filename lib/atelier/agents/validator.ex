defmodule Atelier.Agents.Validator do
  @moduledoc """
  Validator agent responsible for syntax validation of generated code.
  """

  require Logger
  alias Phoenix.PubSub

  def init_state(opts) do
    %{
      role: :validator,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}"
    }
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  def handle_info({:code_ready, _code, filename}, state) do
    extension = Path.extname(filename)
    IO.puts("🧪 Validator: Checking syntax for #{filename}...")
    Logger.debug("Starting validation", filename: filename, extension: extension)

    full_path = Path.expand("/tmp/atelier_studio/#{state.project_id}/#{filename}")
    Logger.debug("Validating file at path", path: full_path)

    # Determine the check command based on extension
    result =
      case extension do
        ".js" ->
          Logger.debug("Running Node validation")
          System.cmd("node", ["--check", full_path])

        ".ex" ->
          Logger.debug("Running Elixir validation")
          System.cmd("elixirc", [full_path, "-o", "/tmp/atelier_studio/build"])

        ".py" ->
          Logger.debug("Running Python validation")
          System.cmd("python3", ["-m", "py_compile", full_path])

        _ ->
          Logger.info("No validator available", filename: filename, extension: extension)
          {"No validator for this file type", 0}
      end

    case result do
      {_output, 0} ->
        IO.puts("✅ Validator: #{filename} syntax is valid.")
        Logger.info("Validation passed", filename: filename)
        PubSub.broadcast(Atelier.PubSub, state.topic, {:validation_passed, filename})

      {error_msg, exit_code} ->
        IO.puts("❌ Validator: #{filename} has syntax errors!")

        Logger.warning("Validation failed",
          filename: filename,
          exit_code: exit_code,
          error: error_msg
        )

        PubSub.broadcast(Atelier.PubSub, state.topic, {:validation_failed, filename, error_msg})
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
