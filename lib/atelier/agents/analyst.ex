defmodule Atelier.Agents.Analyst do
  @moduledoc """
  Analyst agent responsible for collecting failures and generating post-mortem reports.
  """

  @behaviour Atelier.Agent.Worker

  require Logger

  @spec init_state(Keyword.t()) :: map()
  def init_state(opts) do
    %{
      role: :analyst,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}",
      # To store the "struggles"
      failure_log: []
    }
  end

  @spec handle_cast(term(), map()) :: {:noreply, map()}
  def handle_cast(_msg, state), do: {:noreply, state}

  # Collect failures as they happen
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info({:execution_failure, filename, output}, state) do
    entry = %{filename: filename, error: output, time: DateTime.utc_now()}
    {:noreply, %{state | failure_log: [entry | state.failure_log]}}
  end

  # Write the post-mortem when everything is done
  def handle_info(:project_finished, state) do
    if Enum.empty?(state.failure_log) do
      Logger.info("[Analyst] No failures detected. No post-mortem needed.")
    else
      write_report(state)
    end

    {:noreply, state}
  end

  # Ignore other messages that don't require analyst action
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp write_report(state) do
    Logger.info("[Analyst] Generating LESSONS_LEARNED.md...")

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      system = "You are a Senior Software Quality Analyst."

      prompt = """
      The following errors occurred during the project development:
      #{inspect(state.failure_log)}

      Write a 'LESSONS_LEARNED.md' report. Include:
      1. What went wrong?
      2. Why did the LLM likely fail the first time?
      3. How was it resolved?
      4. Advice for future prompts to avoid this.
      """

      report = Atelier.LLM.prompt(system, prompt)
      Atelier.Storage.write_file(state.project_id, "LESSONS_LEARNED.md", report)
    end)
  end
end
