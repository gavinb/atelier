defmodule Atelier.Agents.Clerk do
  @moduledoc """
  Clerk agent responsible for manifest generation and project tracking.
  """

  def handle_cast(_msg, state), do: {:noreply, state}

  def handle_info({:blueprint_ready, files}, state) do
    content = """
    # Project Manifest: #{state.project_id}

    ## Planned Files
    #{Enum.map(files, &"* **#{&1["name"]}**: #{&1["description"]}") |> Enum.join("\n")}

    ## Progress
    """

    Atelier.Storage.write_file(state.project_id, "MANIFEST.md", content)
    {:noreply, state}
  end

  def handle_info({:code_ready, _code}, state) do
    # The Clerk sees code is ready and could update the manifest with stats
    # or checkmarks. For now, we'll just log it.
    IO.puts("📋 Clerk: Updating manifest with new code submission...")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
