defmodule Atelier.Agents.Architect do
  @moduledoc """
  Architect agent responsible for designing system blueprints.
  """
  alias Phoenix.PubSub

  @behaviour Atelier.Agent.Worker

  def init_state(opts) do
    %{
      role: :architect,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}",
      # Temporary storage
      requirement: nil
    }
  end

  def handle_cast({:design_spec, requirement}, state) do
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

  def handle_cast({:request_feature, requirement}, state) do
    Logger.info("[Architect] Requirement received. Deciding if research is needed...")

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      # We ask the LLM: "Do you have enough info, or do you need to search?"
      check_prompt = """
      Requirement: #{requirement}
      Do you need to research specific libraries, APIs, or documentation to implement this?
      If yes, respond with 'SEARCH: <query>'.
      If no, respond with 'PROCEED'.
      """

      case Atelier.LLM.prompt("You are a Lead Architect.", check_prompt) do
        "SEARCH: " <> query ->
          Logger.info("[Architect] Researching: #{query}")
          Phoenix.PubSub.broadcast(Atelier.PubSub, state.topic, {:research_request, query})

        _ ->
          # No research needed, proceed to blueprint
          send(self(), {:generate_blueprint, requirement, ""})
      end
    end)

    {:noreply, state}
  end

  # Handle the Researcher's response
  def handle_info({:research_produced, _query, summary}, state) do
    Logger.info("[Architect] Research received. Designing blueprint with new knowledge...")
    # Now we pass the summary into the final blueprint generation
    generate_blueprint(state.requirement, summary, state)
    {:noreply, state}
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}

  defp generate_blueprint(requirement, research_summary, state) do
    # 1. Combine the requirement AND the research into one context string
    context_prompt = """
    USER REQUIREMENT: #{requirement}
    RESEARCH CONTEXT: #{research_summary}

    Based on the research provided above, create a technical JSON blueprint.
    Ensure you use the specific libraries and patterns found in the research.
    """

    topic = state.topic

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      system = """
      You are a Senior Architect. Output ONLY a JSON object.
      No markdown, no preamble, no explanations.
      Format: {"files": [{"name": "filename.ex", "description": "detailed logic"}]}
      """

      # 2. BUG FIX: Pass the 'context_prompt', not just the 'requirement'
      blueprint_raw = Atelier.LLM.prompt(system, context_prompt)

      # 3. Robust JSON extraction
      json_cleaned =
        blueprint_raw
        |> String.replace(~r/```json|```/, "") # Strip backticks first
        |> String.trim()
        |> then(fn s ->
          # If the LLM added chatter, extract only the JSON object
          case Regex.run(~r/\{.*\}/s, s) do
            [json] -> json
            nil -> s
          end
        end)

      case Jason.decode(json_cleaned) do
        {:ok, %{"files" => files}} ->
          Logger.info("Blueprint ready with #{length(files)} files.")
          Phoenix.PubSub.broadcast(Atelier.PubSub, topic, {:blueprint_ready, files})

        {:error, reason} ->
          Logger.error("JSON Parse Error: #{inspect(reason)}")
          Logger.debug("RAW OUTPUT WAS: #{blueprint_raw}")
          # Option: Broadcast a failure to trigger a retry or alert the CLI
      end
    end)
  end
end
