defmodule Atelier.LLM do
  @doc "Main entry point to talk to any LLM"
  def prompt(system_instructions, user_input, opts \\ []) do
    provider = opts[:provider] || Application.get_env(:atelier, :llm_provider, :ollama)

    case provider do
      :anthropic -> call_anthropic(system_instructions, user_input)
      :ollama -> call_ollama(system_instructions, user_input)
    end
  end

  defp call_anthropic(system, user) do
    api_key = System.get_env("ANTHROPIC_API_KEY")

    Req.post!("https://api.anthropic.com/v1/messages",
      headers: [{"x-api-key", api_key}, {"anthropic-version", "2023-06-01"}],
      json: %{
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 1024,
        system: system,
        messages: [%{role: "user", content: user}]
      }
    ).body["content"]
    |> List.first()
    |> Map.get("text")
  end

  defp call_ollama(system, user) do
    # Ollama uses a single prompt string or a chat list.
    # For a simple prompt, we can use /api/generate
    model = Application.get_env(:atelier, :ollama_model, "llama3")

    full_prompt = "System: #{system}\n\nUser: #{user}"

    Req.post!("http://localhost:11434/api/generate",
      json: %{
        model: model,
        prompt: full_prompt,
        stream: false
      },
      receive_timeout: 60_000
    ).body["response"]
  end
end
