defmodule Atelier.Agents.Researcher do
  require Logger

  def init_state(opts) do
    %{
      role: :researcher,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}"
    }
  end

  # The Architect sends a request for information
  def handle_info({:research_request, query}, state) do
    Logger.info("[Researcher] Searching for: #{query}")

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      # 1. Perform the search (Mocking the API call here)
      results = perform_web_search(query)

      # 2. Use an LLM to summarize the search results into actionable docs
      summary = summarize_results(query, results)

      # 3. Send the knowledge back to the Architect
      Phoenix.PubSub.broadcast(
        Atelier.PubSub,
        state.topic,
        {:research_produced, query, summary}
      )
    end)

    {:noreply, state}
  end

  defp perform_web_search(query) do
    # Here you would call Req.get/2 to a search API
    "Search results for #{query}: Use 'mathjs' for advanced calculations..."
  end

  defp summarize_results(query, results) do
    system = "You are a Research Assistant. Summarize search results into technical specs."
    Atelier.LLM.prompt(system, "Query: #{query}\nResults: #{results}")
  end
end
