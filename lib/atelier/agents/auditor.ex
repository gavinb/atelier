defmodule Atelier.Agents.Auditor do
  @moduledoc """
  Auditor agent responsible for code scanning and suggesting fixes.
  """

  require Logger
  alias Phoenix.PubSub

  @behaviour Atelier.Agent.Worker

  def init_state(opts) do
    %{
      role: :auditor,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}"
    }
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  def handle_info({:llm_error, reason}, state) do
    IO.puts("⚠️  Auditor: Notified of LLM failure: #{reason}")
    Logger.warning("Auditor received LLM error notification", reason: reason)
    {:noreply, state}
  end

  def handle_info({:code_ready, code, _filename}, state) do
    IO.puts("🔍 Auditor: Running infra-scan...")
    Logger.debug("Starting code scan", code_length: String.length(code))

    case Atelier.Native.Scanner.scan_code(code, ["TODO", "FIXME"]) do
      {true, _} ->
        handle_clean_scan()

      {false, issues} ->
        handle_issues_found(issues, code, state.topic)
    end

    {:noreply, state}
  end

  # Ignore messages this agent doesn't handle
  def handle_info(_msg, state), do: {:noreply, state}

  defp handle_clean_scan do
    IO.puts("✅ Auditor: Clean!")
    Logger.info("Code scan passed")
  end

  defp handle_issues_found(issues, code, topic) do
    IO.puts("⚠️  Auditor: Issues found. Spawning async LLM task...")

    Logger.warning("Code issues detected",
      issue_count: length(issues),
      issues: inspect(issues)
    )

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      generate_fix_suggestion(issues, code, topic)
    end)
  end

  defp generate_fix_suggestion(issues, code, topic) do
    try do
      Logger.debug("Starting LLM fix suggestion task")
      instructions = "Senior reviewer. Forbidden: #{inspect(issues)}."
      user_query = "Fix this and return ONLY code: \n\n #{code}"

      suggestion = Atelier.LLM.prompt(instructions, user_query)

      Logger.info("LLM fix suggestion generated",
        suggestion_length: String.length(suggestion)
      )

      PubSub.broadcast(Atelier.PubSub, topic, {:suggestion_offered, suggestion})
    rescue
      e ->
        IO.puts("❌ Auditor Error: LLM request failed. Is Ollama running? (#{inspect(e)})")
        Logger.error("LLM request failed", error: inspect(e))
        PubSub.broadcast(Atelier.PubSub, topic, {:llm_error, "Service unavailable"})
    end
  end
end
