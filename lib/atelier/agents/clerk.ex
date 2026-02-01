defmodule Atelier.Agents.Clerk do
  @moduledoc """
  Clerk agent responsible for manifest generation and project tracking.
  """

  require Logger

  @behaviour Atelier.Agent.Worker

  def init_state(opts) do
    %{
      role: :clerk,
      project_id: opts[:project_id],
      topic: "project:#{opts[:project_id]}",
      pending_files: []
    }
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  def handle_info({:blueprint_ready, files}, state) do
    new_state = Map.put(state, :pending_files, Enum.map(files, & &1["name"]))

    content = """
    # Project Manifest: #{state.project_id}

    ## Planned Files
    #{Enum.map(files, &"* **#{&1["name"]}**: #{&1["description"]}") |> Enum.join("\n")}

    ## Progress
    """

    Atelier.Storage.write_file(state.project_id, "MANIFEST.md", content)
    {:noreply, new_state}
  end

  def handle_info({:code_ready, _code}, state) do
    # The Clerk sees code is ready and could update the manifest with stats
    # or checkmarks. For now, we'll just log it.
    IO.puts("📋 Clerk: Updating manifest with new code submission...")
    {:noreply, state}
  end

  def handle_info({:validation_passed, filename}, state) do
    remaining = List.delete(state.pending_files, filename)

    if Enum.empty?(remaining) do
      Logger.info("🏁 Project Complete: All files generated, validated, and committed.")
      Phoenix.PubSub.broadcast(Atelier.PubSub, state.topic, :project_finished)
    end

    {:noreply, %{state | pending_files: remaining}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
