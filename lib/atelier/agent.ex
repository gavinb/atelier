defmodule Atelier.Agent do
  use GenServer
  alias Phoenix.PubSub

  def start_link(opts) do
    # We use a unique name for each process based on project and role
    name = {:global, {opts[:project_id], opts[:role]}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    project_id = opts[:project_id]
    topic = "project:#{project_id}"

    # Subscribe to the project's specific whiteboard
    PubSub.subscribe(Atelier.PubSub, topic)

    IO.puts("✨ Agent [#{opts[:role]}] joined Atelier for #{project_id}")

    {:ok,
     %{
       role: opts[:role],
       project_id: project_id,
       topic: topic,
       memory: []
     }}
  end

  # --- WRITER LOGIC ---
  @impl true
  def handle_cast({:write_code, filename, code}, state) when state.role == :writer do
    IO.puts("✍️  Writer: Saving #{filename} to local storage...")

    # Simulate "Disk I/O"
    Atelier.Storage.write_file(state.project_id, filename, code)

    # Tell the world where the file is
    PubSub.broadcast(Atelier.PubSub, state.topic, {:file_updated, filename})
    {:noreply, state}
  end

  # --- AUDITOR LOGIC ---
  @impl true
  def handle_info({:file_updated, filename}, %{role: :auditor} = state) do
    IO.puts("🔍 Auditor: Spotted update to #{filename}. Fetching content...")

    case Atelier.Storage.read_file(state.project_id, filename) do
      {:ok, code} ->
        # Run our Rust NIF on the actual file content
        case Atelier.Native.Scanner.scan_code(code, ["API_KEY", "TODO"]) do
          {true, _} -> IO.puts("✅ Auditor: #{filename} passed local scan.")
          {false, issues} -> IO.puts("❌ Auditor: #{filename} failed! Found #{inspect(issues)}")
        end

      _ ->
        :error
    end

    {:noreply, state}
  end

  # --- WRITER LOGIC ---
  # Triggered manually for now to simulate work
  # lib/atelier/agent.ex

  @impl true
  def handle_cast({:write_code, filename, code}, state) when state.role == :writer do
    IO.puts("✍️  Writer: Saving #{filename} to local storage...")

    # Write to our tmp/ directory
    Atelier.Storage.write_file(state.project_id, filename, code)

    # Broadcast to the Auditor
    PubSub.broadcast(Atelier.PubSub, state.topic, {:code_ready, code})
    {:noreply, state}
  end

  # --- AUDITOR LOGIC ---
  @impl true
  def handle_info({:code_ready, code}, %{role: :auditor} = state) do
    IO.puts("🔍 Auditor: Running infra-scan...")

    case Atelier.Native.Scanner.scan_code(code, ["TODO", "FIXME"]) do
      {true, _} ->
        IO.puts("✅ Auditor: Clean!")

      {false, issues} ->
        IO.puts("⚠️ Auditor: Rust found issues #{inspect(issues)}. Asking Claude for a fix...")

        # The "Brain" part
        instructions =
          "You are a senior code reviewer. The user has forbidden patterns: #{inspect(issues)}."

        user_query = "Fix this code and return ONLY the code: \n\n #{code}"

        suggestion = Atelier.LLM.prompt(instructions, user_query)

        # Broadcast the fix back to the project whiteboard
        PubSub.broadcast(Atelier.PubSub, state.topic, {:suggestion_offered, suggestion})
    end

    {:noreply, state}
  end

  # The Writer now needs to listen for suggestions!
  def handle_info({:suggestion_offered, suggestion}, %{role: :writer} = state) do
    IO.puts("✍️ Writer: Received a fix from the Auditor. Applying...")
    # In a real app, this would update the file in our local storage
    {:noreply, state}
  end

  # Catch-all for other messages
  @impl true
  def handle_info(msg, state) do
    # Log incoming messages just to see the flow
    # IO.inspect(msg, label: "Agent #{state.role} received")
    {:noreply, state}
  end
end
