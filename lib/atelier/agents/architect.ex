defmodule Atelier.Agents.Architect do
  @moduledoc """
  Architect agent responsible for designing system blueprints.
  """

  alias Phoenix.PubSub

  def init_state(opts) do
    %{
      role: :architect,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}"
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

  def handle_cast(_msg, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}
end
