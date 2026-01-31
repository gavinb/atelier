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

    {:ok,
     %{
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

  @impl true
  def handle_cast({:design_spec, requirement}, state) when state.role == :architect do
    IO.puts("📐 Architect: Designing system for: #{requirement}")
    topic = state.topic

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      system = """
      You are a Senior Architect. Output ONLY a JSON object.
      No markdown, no preamble, no explanations.
      Format: {"files": [{"name": "filename.ex", "description": "logic"}]}
      """

      blueprint_raw = Atelier.LLM.prompt(system, requirement)

      # Clean the response:
      # 1. Look for content between ```json and ```
      # 2. Or just try to find the first '{' and last '}'
      json_cleaned =
        blueprint_raw
        # Extract anything between curly braces
        |> String.replace(~r/^.*?({.*}).*$/s, "\\1")
        # Strip markdown backticks
        |> String.replace(~r/```json|```/, "")
        |> String.trim()

      case Jason.decode(json_cleaned) do
        {:ok, %{"files" => files}} ->
          IO.puts("📐 Architect: Blueprint ready with #{length(files)} files.")
          PubSub.broadcast(Atelier.PubSub, topic, {:blueprint_ready, files})

        {:error, reason} ->
          IO.puts("❌ Architect: JSON Parse Error: #{inspect(reason)}")
          IO.puts("RAW OUTPUT WAS: #{blueprint_raw}")
      end
    end)

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

  @impl true
  def handle_info({:llm_error, reason}, state) do
    IO.puts("⚠️  Agent [#{state.role}]: Notified of LLM failure: #{reason}")
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
  def handle_info({:blueprint_ready, files}, %{role: :writer} = state) do
    IO.puts("✍️  Writer: I have my marching orders. Starting work...")

    # For simplicity, we'll just start the first file.
    # In a real Atelier, you might queue these.
    Enum.each(files, fn file_spec ->
      send(self(), {:execute_task, file_spec})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:execute_task, %{"name" => name, "description" => desc}}, state) do
    IO.puts("✍️  Writer: Generating code for #{name}...")

    topic = state.topic
    project_id = state.project_id

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      system = "You are a specialized Elixir Writer. Implement the requested file."
      code = Atelier.LLM.prompt(system, "Create the file '#{name}' which does: #{desc}")

      # Save it locally
      Atelier.Storage.write_file(project_id, name, code)

      # Broadcast for the Auditor to check
      PubSub.broadcast(Atelier.PubSub, topic, {:code_ready, code})
    end)

    {:noreply, state}
  end

  # lib/atelier/agent.ex

  # --- CLERK LOGIC ---
  @impl true
  def handle_info({:blueprint_ready, files}, %{role: :clerk} = state) do
    content = """
    # Project Manifest: #{state.project_id}

    ## Planned Files
    #{Enum.map(files, &"* **#{&1["name"]}**: #{&1["description"]}") |> Enum.join("\n")}

    ## Progress
    """

    Atelier.Storage.write_file(state.project_id, "MANIFEST.md", content)
    {:noreply, state}
  end

  def handle_info({:code_ready, _code}, %{role: :clerk} = state) do
    # The Clerk sees code is ready and could update the manifest with stats
    # or checkmarks. For now, we'll just log it.
    IO.puts("📋 Clerk: Updating manifest with new code submission...")
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    # Prefixed with _ to silence the unused variable warning
    {:noreply, state}
  end
end
