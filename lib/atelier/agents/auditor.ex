defmodule Atelier.Agents.Auditor do
  @moduledoc """
  Auditor agent responsible for code scanning and suggesting fixes.
  """

  alias Phoenix.PubSub

  def handle_cast(_msg, state), do: {:noreply, state}

  def handle_info({:code_ready, code}, state) do
    IO.puts("🔍 Auditor: Running infra-scan...")

    case Atelier.Native.Scanner.scan_code(code, ["TODO", "FIXME"]) do
      {true, _} ->
        IO.puts("✅ Auditor: Clean!")

      {false, issues} ->
        IO.puts("⚠️  Auditor: Issues found. Spawning async LLM task...")

        # We capture the state needed so the task has context
        topic = state.topic

        Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
          try do
            instructions = "Senior reviewer. Forbidden: #{inspect(issues)}."
            user_query = "Fix this and return ONLY code: \n\n #{code}"

            # This call is now async!
            suggestion = Atelier.LLM.prompt(instructions, user_query)

            PubSub.broadcast(Atelier.PubSub, topic, {:suggestion_offered, suggestion})
          rescue
            e ->
              IO.puts("❌ Auditor Error: LLM request failed. Is Ollama running? (#{inspect(e)})")
              PubSub.broadcast(Atelier.PubSub, topic, {:llm_error, "Service unavailable"})
          end
        end)
    end

    {:noreply, state}
  end

  def handle_info({:llm_error, reason}, state) do
    IO.puts("⚠️  Auditor: Notified of LLM failure: #{reason}")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
