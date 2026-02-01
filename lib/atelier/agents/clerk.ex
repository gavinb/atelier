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
    #{Enum.map_join(files, "\n", &"* **#{&1["name"]}**: #{&1["description"]}")}

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

    # Always broadcast :file_validated so GitBot and Runner process every file
    Phoenix.PubSub.broadcast(Atelier.PubSub, state.topic, {:file_validated, filename})

    if Enum.empty?(remaining) do
      Logger.info("🏁 Project Complete: All files generated, validated, and committed.")
      Phoenix.PubSub.broadcast(Atelier.PubSub, state.topic, :project_finished)
    end

    {:noreply, %{state | pending_files: remaining}}
  end

  def handle_info({:agent_surrender, filename, error}, state) do
    Logger.error("[Clerk] Writer surrendered on #{filename}. Stopping project.")

    summary = """

    ## Final Status
    - **Status:** ❌ Failed - Max retries exceeded
    - **Failed File:** #{filename}
    - **Error:** #{error}
    - **Timestamp:** #{DateTime.now!("Etc/UTC")}
    - **Remaining Files:** #{inspect(state.pending_files)}
    """

    # Append to the existing manifest
    path = Path.expand("/tmp/atelier_studio/#{state.project_id}/MANIFEST.md")
    File.write!(path, summary, [:append])

    # Broadcast project_finished to signal all agents to stop
    Phoenix.PubSub.broadcast(Atelier.PubSub, state.topic, :project_finished)

    {:noreply, state}
  end

  def handle_info(:project_finished, state) do
    summary = """

    ## Final Status
    - **Status:** 🏆 Completed Successfully
    - **Timestamp:** #{DateTime.now!("Etc/UTC")}
    - **Agents Involved:** Architect, Writer, Auditor, Validator, Runner, GitBot
    """

    # Append to the existing manifest
    path = Path.expand("/tmp/atelier_studio/#{state.project_id}/MANIFEST.md")
    File.write!(path, summary, [:append])

    Logger.info("[Clerk] Final manifest signed and sealed.")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
