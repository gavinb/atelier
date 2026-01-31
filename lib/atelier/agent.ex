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

  # --- WRITER: Receiving the Blueprint ---
  @impl true
  def handle_info({:blueprint_ready, files}, %{role: :writer} = state) do
    IO.puts(
      "✍️  Writer: Marching orders received. Processing #{length(files)} files sequentially..."
    )

    send(self(), {:process_next_task, files})
    {:noreply, state}
  end

  # --- WRITER: The Recursive Queue ---
  def handle_info({:process_next_task, []}, state) do
    IO.puts("✍️  Writer: All tasks in blueprint completed.")
    {:noreply, state}
  end

  def handle_info({:process_next_task, [task | remaining]}, state) do
    %{"name" => name, "description" => desc} = task
    IO.puts("✍️  Writer: Generating [#{name}]...")

    # We still use a Task for the LLM call so the Writer process stays responsive,
    # but we tell the Task to report back to the Writer when it's done.
    parent = self()
    topic = state.topic
    project_id = state.project_id

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      system = "You are a specialized code generator. Output ONLY raw source code. No talk."

      try do
        raw_response = Atelier.LLM.prompt(system, "Implement '#{name}': #{desc}")
        clean_code = Atelier.LLM.clean_code(raw_response)

        Atelier.Storage.write_file(project_id, name, clean_code)
        PubSub.broadcast(Atelier.PubSub, topic, {:code_ready, clean_code, name})

        # Tell the Writer to move to the next file
        send(parent, {:task_complete, remaining})
      rescue
        e ->
          IO.puts("❌ Writer: Failed [#{name}] - #{inspect(e)}")
          # Continue anyway
          send(parent, {:task_complete, remaining})
      end
    end)

    {:noreply, state}
  end

  # --- WRITER: Moving to the next item ---
  def handle_info({:task_complete, remaining}, state) do
    send(self(), {:process_next_task, remaining})
    {:noreply, state}
  end

  def handle_info({:process_queue, []}, state) do
    IO.puts("✍️  Writer: All tasks complete.")
    {:noreply, state}
  end

  def handle_info({:process_queue, [current_file | remaining]}, state) do
    # Execute only the current file
    execute_file_generation(current_file, state)

    # After a short delay or upon completion, we'll trigger the next one.
    # For now, let's just trigger the next one immediately (Task handles the async part)
    # but since LLM is the bottleneck, this is still better than a blind Enum.each.
    send(self(), {:process_queue, remaining})

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

  # --- VALIDATOR LOGIC ---
  @impl true
  def handle_info({:code_ready, _code, filename}, %{role: :validator} = state) do
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

  @impl true
  def handle_info(_msg, state) do
    # Prefixed with _ to silence the unused variable warning
    {:noreply, state}
  end

  # Extract the logic to a private helper
  defp execute_file_generation(%{"name" => name, "description" => desc}, state) do
    IO.puts("✍️  Writer: Generating code for #{name}...")
    topic = state.topic
    project_id = state.project_id

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      # NEW: Stricter System Prompt to fix the "Preamble" issue
      system = """
      You are a specialized code generator.
      Output ONLY the raw source code.
      Do NOT include explanations, markdown backticks, or 'Here is your code'.
      Strictly follow the file extension rules.
      """

      try do
        code = Atelier.LLM.prompt(system, "Implement the file '#{name}': #{desc}")

        # Strip markdown backticks if the LLM ignores instructions
        clean_code = String.replace(code, ~r/```[a-z]*\n|```/i, "") |> String.trim()

        Atelier.Storage.write_file(project_id, name, clean_code)
        PubSub.broadcast(Atelier.PubSub, topic, {:code_ready, clean_code})
      rescue
        e -> IO.puts("❌ Writer Error on #{name}: #{inspect(e)}")
      end
    end)
  end
end
