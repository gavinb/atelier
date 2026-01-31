defmodule Atelier.Agents.GitBot do
  @moduledoc """
  GitBot agent responsible for auto-committing validated code.
  """

  def handle_cast(_msg, state), do: {:noreply, state}

  def handle_info({:validation_passed, filename}, state) do
    IO.puts("📦 GitBot: #{filename} passed validation. Preparing commit...")

    project_path = Path.expand("tmp/atelier_studio/#{state.project_id}")

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      # 1. Ask the LLM for a sensible commit message
      {:ok, code} = Atelier.Storage.read_file(state.project_id, filename)

      prompt = """
      Generate a concise, professional Git commit message for this file: #{filename}.
      The code does: #{String.slice(code, 0, 200)}...
      Return ONLY the commit message text.
      """

      commit_msg = Atelier.LLM.prompt("You are a Git expert.", prompt) |> String.trim()

      # 2. Execute the Git commands
      # We use 'cd' in System.cmd to ensure we're in the right folder
      try do
        System.cmd("git", ["add", filename], cd: project_path)
        System.cmd("git", ["commit", "-m", commit_msg], cd: project_path)

        IO.puts("🚀 GitBot: Committed #{filename} with message: \"#{commit_msg}\"")
      rescue
        e -> IO.puts("❌ GitBot: Failed to commit. Is Git initialized? #{inspect(e)}")
      end
    end)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
