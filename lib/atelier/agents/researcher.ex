defmodule Atelier.Agents.Researcher do
  @moduledoc """
  Researcher agent responsible for performing web searches for the Architect.

  Uses DuckDuckGo's Instant Answer API for search results, which provides
  abstracts, definitions, and related topics without requiring an API key.
  """

  require Logger

  @behaviour Atelier.Agent.Worker

  @duckduckgo_api "https://api.duckduckgo.com/"

  @spec init_state(Keyword.t()) :: map()
  def init_state(opts) do
    %{
      role: :researcher,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}"
    }
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  # The Architect sends a request for information
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info({:research_request, query}, state) do
    Logger.info("[Researcher] Searching for: #{query}")
    IO.puts("🔍 Researcher: Searching for '#{query}'...")

    topic = state.topic

    Task.Supervisor.start_child(Atelier.LLMTaskSupervisor, fn ->
      # 1. Perform the search
      results = perform_web_search(query)

      # 2. Use an LLM to summarize the search results into actionable docs
      summary = summarize_results(query, results)

      IO.puts("🔍 Researcher: Research complete for '#{query}'")

      # 3. Send the knowledge back to the Architect
      Phoenix.PubSub.broadcast(
        Atelier.PubSub,
        topic,
        {:research_produced, query, summary}
      )
    end)

    {:noreply, state}
  end

  # Ignore messages this agent doesn't handle
  def handle_info(_msg, state), do: {:noreply, state}

  @spec perform_web_search(String.t()) :: String.t()
  defp perform_web_search(query) do
    Logger.debug("[Researcher] Querying DuckDuckGo API", query: query)

    case Req.get(@duckduckgo_api,
           params: [
             q: query,
             format: "json",
             no_html: 1,
             skip_disambig: 1
           ],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        parse_duckduckgo_response(body, query)

      {:error, reason} ->
        Logger.warning("[Researcher] DuckDuckGo API failed", error: inspect(reason))
        "No search results available. Error: #{inspect(reason)}"
    end
  end

  defp parse_duckduckgo_response(body, query) do
    # Extract useful information from DuckDuckGo's response
    _abstract = body["Abstract"] || ""
    abstract_text = body["AbstractText"] || ""
    definition = body["Definition"] || ""
    answer = body["Answer"] || ""

    # Get related topics
    related_topics =
      (body["RelatedTopics"] || [])
      |> Enum.take(5)
      |> Enum.map(fn
        %{"Text" => text} -> "- #{text}"
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    # Build a structured result
    result = """
    Search Query: #{query}

    #{if abstract_text != "", do: "## Summary\n#{abstract_text}\n", else: ""}
    #{if definition != "", do: "## Definition\n#{definition}\n", else: ""}
    #{if answer != "", do: "## Direct Answer\n#{answer}\n", else: ""}
    #{if related_topics != "", do: "## Related Information\n#{related_topics}\n", else: ""}
    """

    result = String.trim(result)

    if result == "Search Query: #{query}" do
      Logger.debug("[Researcher] No direct results from DuckDuckGo, returning query context")
      "Search for '#{query}' returned no direct results. The Architect should use general knowledge about this topic."
    else
      Logger.debug("[Researcher] Found search results", result_length: String.length(result))
      result
    end
  end

  @spec summarize_results(String.t(), String.t()) :: String.t()
  defp summarize_results(query, results) do
    system = """
    You are a Technical Research Assistant. Your job is to:
    1. Extract actionable technical information from search results
    2. Identify relevant libraries, frameworks, or APIs mentioned
    3. Summarize best practices or implementation patterns
    4. Note any version requirements or compatibility concerns

    Be concise and focus on information useful for code generation.
    """

    prompt = """
    Original Query: #{query}

    Search Results:
    #{results}

    Provide a technical summary that would help a code generator implement a solution.
    """

    Atelier.LLM.prompt(system, prompt)
  end
end
