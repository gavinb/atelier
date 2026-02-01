defmodule Atelier.LLM do
  @moduledoc """
  Abstraction layer for LLM providers (Ollama and Anthropic).
  """

  require Logger

  # Default timeout of 2 minutes for LLM calls
  @default_timeout_ms 120_000

  @doc """
  Main entry point to talk to any LLM.

  ## Options
    * `:provider` - Override the configured provider (`:ollama` or `:anthropic`)
    * `:timeout` - Request timeout in milliseconds (default: #{@default_timeout_ms})
  """
  @spec prompt(String.t(), String.t(), keyword()) :: String.t() | {:error, :timeout | term()}
  def prompt(system_instructions, user_input, opts \\ []) do
    provider = opts[:provider] || Application.get_env(:atelier, :llm_provider, :ollama)
    timeout = opts[:timeout] || Application.get_env(:atelier, :llm_timeout, @default_timeout_ms)

    Logger.debug("Sending LLM prompt",
      provider: provider,
      input_length: String.length(user_input),
      timeout: timeout
    )

    result =
      case provider do
        :anthropic -> call_anthropic(system_instructions, user_input, timeout)
        :ollama -> call_ollama(system_instructions, user_input, timeout)
      end

    case result do
      {:ok, text} ->
        Logger.debug("Received LLM response",
          provider: provider,
          response_length: String.length(text)
        )
        text

      {:error, reason} ->
        Logger.error("LLM call failed", provider: provider, reason: inspect(reason))
        raise "LLM call failed: #{inspect(reason)}"
    end
  end

  defp call_anthropic(system, user, timeout) do
    api_key = System.get_env("ANTHROPIC_API_KEY")
    Logger.debug("Calling Anthropic API")

    case Req.post("https://api.anthropic.com/v1/messages",
           headers: [{"x-api-key", api_key}, {"anthropic-version", "2023-06-01"}],
           json: %{
             model: "claude-3-5-sonnet-20241022",
             max_tokens: 1024,
             system: system,
             messages: [%{role: "user", content: user}]
           },
           receive_timeout: timeout
         ) do
      {:ok, %{status: 200, body: body}} ->
        text = body["content"] |> List.first() |> Map.get("text")
        Logger.debug("Anthropic response received")
        {:ok, text}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        Logger.error("Anthropic API timeout after #{timeout}ms")
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_ollama(system, user, timeout) do
    model = Application.get_env(:atelier, :ollama_model, "llama3")
    endpoint = Application.get_env(:atelier, :ollama_endpoint, "http://localhost:11434")

    Logger.debug("Calling Ollama API", model: model)
    full_prompt = "System: #{system}\n\nUser: #{user}"

    case Req.post("#{endpoint}/api/generate",
           json: %{
             model: model,
             prompt: full_prompt,
             stream: false
           },
           receive_timeout: timeout
         ) do
      {:ok, %{status: 200, body: body}} ->
        text = body["response"]
        Logger.debug("Ollama response received", model: model)
        {:ok, text}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        Logger.error("Ollama API timeout after #{timeout}ms", model: model)
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("Ollama API call failed", error: inspect(reason), model: model)
        {:error, reason}
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
