defmodule Atelier.Agent do
  use GenServer
  alias Phoenix.PubSub

  def start_link(opts) do
    name = {:global, {opts[:project_id], opts[:role]}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    project_id = opts[:project_id]
    topic = "project:#{project_id}"
    PubSub.subscribe(Atelier.PubSub, topic)

    IO.puts("✨ Agent [#{opts[:role]}] joined Atelier for #{project_id}")

    {:ok, %{
      role: opts[:role],
      project_id: project_id,
      topic: topic,
      memory: []
    }}
  end

  # --- ALL CASTS GO HERE ---
  @impl true
  def handle_cast({:write_code, filename, code}, state) when state.role == :writer do
    IO.puts("✍️  Writer: Saving #{filename} to local storage...")

    # We removed the case match because write_file now uses ! methods and returns {:ok, path}
    {:ok, full_path} = Atelier.Storage.write_file(state.project_id, filename, code)

    IO.puts("✍️  Writer: Saved to #{full_path}")
    PubSub.broadcast(Atelier.PubSub, state.topic, {:code_ready, code})
    {:noreply, state}
  end

  # --- ALL INFOS GO HERE ---
  @impl true
  def handle_info({:code_ready, code}, %{role: :auditor} = state) do
    IO.puts("🔍 Auditor: Running infra-scan...")

    case Atelier.Native.Scanner.scan_code(code, ["TODO", "FIXME"]) do
      {true, _} ->
        IO.puts("✅ Auditor: Clean!")

      {false, issues} ->
        IO.puts("⚠️  Auditor: Rust found issues #{inspect(issues)}. Asking LLM for a fix...")

        instructions = "You are a senior code reviewer. The user has forbidden patterns: #{inspect(issues)}."
        user_query = "Fix this code and return ONLY the code: \n\n #{code}"

        # This might take a second if Ollama is cold-starting
        suggestion = Atelier.LLM.prompt(instructions, user_query)

        PubSub.broadcast(Atelier.PubSub, state.topic, {:suggestion_offered, suggestion})
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:suggestion_offered, suggestion}, %{role: :writer} = state) do
    IO.puts("✍️  Writer: Received a fix from the Auditor.")
    IO.puts("📝 Suggested Fix:\n#{suggestion}")

    # For now, we just log it. Later we can make the writer auto-apply it.
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    # Prefixed with _ to silence the unused variable warning
    {:noreply, state}
  end
end
