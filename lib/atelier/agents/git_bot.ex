defmodule Atelier.Agents.GitBot do
  @moduledoc """
  GitBot agent responsible for auto-committing validated code.
  """

  @behaviour Atelier.Agent.Worker

  require Logger

  @spec init_state(Keyword.t()) :: map()
  def init_state(opts) do
    %{
      role: :git_bot,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}",
      project_finished: false
    }
  end

  @spec handle_cast(term(), map()) :: {:noreply, map()}
  def handle_cast(_msg, state), do: {:noreply, state}

  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info({:file_validated, filename}, state) do
    IO.puts("📦 GitBot: #{filename} validated. Preparing commit...")

    Logger.info("Validation passed, preparing commit",
      filename: filename,
      project_id: state.project_id
    )

    project_path = Path.expand("/tmp/atelier_studio/#{state.project_id}")

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      perform_commit(filename, project_path, state.project_id)
    end)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp perform_commit(filename, project_path, project_id) do
    Logger.debug("Starting commit task", filename: filename, project_path: project_path)

    {:ok, code} = Atelier.Storage.read_file(project_id, filename)
    commit_msg = generate_commit_message(filename, code)

    execute_git_commit(filename, project_path, commit_msg)
  end

  defp generate_commit_message(filename, code) do
    prompt = """
    Generate a concise, professional Git commit message for this file: #{filename}.
    The code does: #{String.slice(code, 0, 200)}...
    Return ONLY the commit message text.
    """

    Logger.debug("Requesting commit message from LLM", filename: filename)
    commit_msg = String.trim(Atelier.LLM.prompt("You are a Git expert.", prompt))
    Logger.debug("Commit message generated", message: commit_msg)
    commit_msg
  end

  defp execute_git_commit(filename, project_path, commit_msg) do
    try do
      Logger.debug("Running git add", filename: filename)

      {add_output, status1} =
        System.cmd("git", ["add", filename], cd: project_path, env: [], stderr_to_stdout: true)

      if status1 != 0 do
        Logger.warning("Git add had non-zero status", output: add_output, status: status1)
      end

      Logger.debug("Running git commit", message: commit_msg)

      {commit_output, status2} =
        System.cmd("git", ["commit", "-m", commit_msg],
          cd: project_path,
          env: [],
          stderr_to_stdout: true
        )

      if status1 == 0 and status2 == 0 do
        IO.puts("🚀 GitBot: Committed #{filename} with message: \"#{commit_msg}\"")
        Logger.info("File successfully committed", filename: filename, message: commit_msg)
      else
        Logger.error("Git commands failed",
          filename: filename,
          add_status: status1,
          add_output: add_output,
          commit_status: status2,
          commit_output: commit_output
        )
      end
    rescue
      e ->
        IO.puts("❌ GitBot: Failed to commit. Is Git initialized? #{inspect(e)}")
        Logger.error("Commit failed with exception", filename: filename, error: inspect(e))
    end
  end
end
