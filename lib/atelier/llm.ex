defmodule Atelier.LLM do
  @model "claude-3-5-sonnet-20241022"

  def prompt(system_instructions, user_input) do
    api_key = System.get_env("ANTHROPIC_API_KEY")

    Req.post!("https://api.anthropic.com/v1/messages",
      headers: [
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"}
      ],
      json: %{
        model: @model,
        max_tokens: 1024,
        system: system_instructions,
        messages: [%{role: "user", content: user_input}]
      }
    ).body["content"] |> List.first() |> Map.get("text")
  end
end
