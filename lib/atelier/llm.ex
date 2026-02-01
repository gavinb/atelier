defmodule Atelier.LLM do
  require Logger

  @doc "Main entry point to talk to any LLM"
  @spec prompt(String.t(), String.t(), keyword()) :: String.t()
  def prompt(system_instructions, user_input, opts \\ []) do
    provider = opts[:provider] || Application.get_env(:atelier, :llm_provider, :ollama)

    Logger.debug("Sending LLM prompt",
      provider: provider,
      input_length: String.length(user_input)
    )

    result =
      case provider do
        :anthropic -> call_anthropic(system_instructions, user_input)
        :ollama -> call_ollama(system_instructions, user_input)
      end

    Logger.debug("Received LLM response",
      provider: provider,
      response_length: String.length(result)
    )

    result
  end

  defp call_anthropic(system, user) do
    api_key = System.get_env("ANTHROPIC_API_KEY")
    Logger.debug("Calling Anthropic API")

    try do
      response =
        Req.post!("https://api.anthropic.com/v1/messages",
          headers: [{"x-api-key", api_key}, {"anthropic-version", "2023-06-01"}],
          json: %{
            model: "claude-3-5-sonnet-20241022",
            max_tokens: 1024,
            system: system,
            messages: [%{role: "user", content: user}]
          }
        )

      text = response.body["content"] |> List.first() |> Map.get("text")
      Logger.debug("Anthropic response received")
      text
    rescue
      e ->
        Logger.error("Anthropic API call failed", error: inspect(e))
        reraise e, __STACKTRACE__
    end
  end

  defp call_ollama(system, user) do
    # Ollama uses a single prompt string or a chat list.
    # For a simple prompt, we can use /api/generate
    model = Application.get_env(:atelier, :ollama_model, "llama3")

    Logger.debug("Calling Ollama API", model: model)
    full_prompt = "System: #{system}\n\nUser: #{user}"

    try do
      response =
        Req.post!("http://localhost:11434/api/generate",
          json: %{
            model: model,
            prompt: full_prompt,
            stream: false
          },
          receive_timeout: 60_000
        )

      text = response.body["response"]
      Logger.debug("Ollama response received", model: model)
      text
    rescue
      e ->
        Logger.error("Ollama API call failed", error: inspect(e), model: model)
        reraise e, __STACKTRACE__
    end
  end

  @spec clean_code(String.t()) :: String.t()
  def clean_code(text) do
    # 1. Try to extract content between triple backticks
    # 2. If no backticks, just trim the whitespace
    case Regex.run(~r/```(?:[a-zA-Z0-9.\-+#]+)?\n?(.*?)```/s, text) do
      [_, code] -> String.trim(code)
      nil -> String.trim(text)
    end
  end
end
