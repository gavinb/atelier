defmodule Atelier.Agents.Writer do
  @moduledoc """
  Writer agent responsible for code generation, blueprint processing, and validation fixes.
  """

  alias Phoenix.PubSub
  require Logger

  @behaviour Atelier.Agent.Worker

  @doc """
  Returns the initial state specific to the Writer role.
  """
  def init_state(opts) do
    %{
      role: :writer,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}",
      # --- Retry Logic State ---
      # Map of %{"filename.ex" => count}
      retries: %{},
      # Threshold before surrendering
      max_retries: 3,
      # The file currently being worked on
      current_task: nil,
      # Pending files from the architect
      queue: []
    }
  end

  def handle_cast({:write_code, filename, code}, state) do
    IO.puts("✍️  Writer: Saving #{filename} to local storage...")

    # We removed the case match because write_file now uses ! methods and returns {:ok, path}
    {:ok, full_path} = Atelier.Storage.write_file(state.project_id, filename, code)

    IO.puts("✍️  Writer: Saved to #{full_path}")
    PubSub.broadcast(Atelier.PubSub, state.topic, {:code_ready, code})
    {:noreply, state}
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  # Receiving suggestion from Auditor
  def handle_info({:suggestion_offered, suggestion}, state) do
    IO.puts("✍️  Writer: Received a fix from the Auditor.")
    IO.puts("📝 Suggested Fix:\n#{suggestion}")

    # For now, we just log it. Later we can make the writer auto-apply it.
    {:noreply, state}
  end

  # Receiving the Blueprint
  def handle_info({:blueprint_ready, files}, state) do
    IO.puts(
      "✍️  Writer: Marching orders received. Processing #{length(files)} files sequentially..."
    )

    send(self(), {:process_next_task, files})
    {:noreply, state}
  end

  # The Recursive Queue
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

  # Moving to the next item
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

  # Handling Validation Failure
  def handle_info({:validation_failed, filename, error_msg}, state) do
    IO.puts("🩹 Writer: My code for #{filename} failed validation. Attempting a fix...")

    topic = state.topic
    project_id = state.project_id

    # We read what we last wrote to provide context to the LLM
    {:ok, current_code} = Atelier.Storage.read_file(project_id, filename)

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      system = "You are a debugger. Fix the provided code based on the compiler error."

      prompt = """
      File: #{filename}
      Error: #{error_msg}

      Current Code:
      #{current_code}

      Please provide the corrected version. Output ONLY the code.
      """

      try do
        raw_response = Atelier.LLM.prompt(system, prompt)
        fixed_code = Atelier.LLM.clean_code(raw_response)

        # Overwrite the bad file with the fix
        Atelier.Storage.write_file(project_id, filename, fixed_code)

        # Re-broadcast to trigger the Auditor and Validator again
        PubSub.broadcast(Atelier.PubSub, topic, {:code_ready, fixed_code, filename})
      rescue
        e -> IO.puts("❌ Writer: Auto-fix failed for #{filename}: #{inspect(e)}")
      end
    end)

    {:noreply, state}
  end

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

  def handle_info({:execution_failure, filename, output}, state) do
    current_attempts = Map.get(state.retries, filename, 0)

    if current_attempts < state.max_retries do
      new_attempts = current_attempts + 1
      Logger.warning("[Writer] Attempt #{new_attempts}/#{state.max_retries} to fix #{filename}")

      # Proceed with the LLM call...
      perform_repair(filename, output, state)

      # Update state with the new attempt count
      {:noreply, %{state | retries: Map.put(state.retries, filename, new_attempts)}}
    else
      Logger.error("[Writer] Max retries reached for #{filename}. Surrendering to human.")

      Phoenix.PubSub.broadcast(
        Atelier.PubSub,
        state.topic,
        {:agent_surrender, filename, output}
      )

      {:noreply, state}
    end
  end

  def handle_info({:execution_success, filename, _output}, state) do
    Logger.info("[Writer] Success confirmed for #{filename}. Resetting retry counter.")
    {:noreply, %{state | retries: Map.delete(state.retries, filename)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Private helper
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

  defp perform_repair(filename, output, state) do
    project_id = state.project_id
    topic = state.topic

    # 1. Grab the code that just failed
    {:ok, failed_code} = Atelier.Storage.read_file(project_id, filename)

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      system_prompt = """
      You are an expert debugger. The code you wrote passed syntax checks but failed during execution.
      Fix the logic errors. Output ONLY the raw corrected source code.
      """

      user_prompt = """
      The following code for '#{filename}' crashed:

      --- CODE ---
      #{failed_code}

      --- RUNTIME ERROR ---
      #{output}

      Identify the bug (e.g., undefined variables, type errors, or logic flaws) and provide the complete fixed file.
      """

      try do
        # 2. Ask the LLM to fix its mistake
        raw_fix = Atelier.LLM.prompt(system_prompt, user_prompt)
        clean_fix = Atelier.LLM.clean_code(raw_fix)

        # 3. Overwrite the file
        Atelier.Storage.write_file(project_id, filename, clean_fix)
        Logger.info("[Writer] Applied runtime fix to #{filename}. Re-validating...")

        # 4. Trigger the cycle again (Validator -> Runner)
        Phoenix.PubSub.broadcast(Atelier.PubSub, topic, {:code_ready, clean_fix, filename})
      rescue
        e -> Logger.error("[Writer] Failed to process auto-fix: #{inspect(e)}")
      end
    end)

    {:noreply, state}
  end
end
