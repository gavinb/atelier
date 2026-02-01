defmodule Mix.Tasks.Atelier.Run do
  use Mix.Task
  require Logger

  @shortdoc "Runs a studio project from the command line"

  def run([requirement]) do
    # 1. Start the application
    Application.ensure_all_started(:atelier)

    project_id = "cli-#{:erlang.unique_integer([:positive])}"

    # 2. Subscribe the CLI process to the project topic so we can hear progress
    Phoenix.PubSub.subscribe(Atelier.PubSub, "project:#{project_id}")

    # 3. Start the project
    Atelier.Studio.start_project(project_id)

    # 1. Trigger the Health Check
    env_pid = GenServer.whereis({:global, {project_id, :environment}})
    GenServer.cast(env_pid, :check_health)

    wait_for_infra(project_id, requirement)
  end

  defp wait_for_infra(project_id, requirement) do
    receive do
      :infra_ready ->
        IO.puts("🚀 Infra ready. Architecting...")
        Atelier.Studio.request_feature(project_id, requirement)
        wait_for_completion(project_id)

      {:infra_error, reason} ->
        IO.puts("\n🛑 ABORTED: #{reason}")
        IO.puts("Please check your local Ollama instance or API keys.")
    end
  end

  defp wait_for_completion(project_id) do
    receive do
      {:project_update, %{status: :completed}} ->
        IO.puts("\n✅ Project completed successfully!")

      {:project_update, %{status: :failed, error: reason}} ->
        IO.puts("\n❌ Project failed: #{reason}")

      {:project_update, _update} ->
        # Log other updates if necessary, or just keep waiting
        wait_for_completion(project_id)
    end
  end
end
