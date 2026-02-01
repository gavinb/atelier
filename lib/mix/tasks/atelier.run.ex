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
      :project_finished ->
        IO.puts("\n✅ Project completed successfully!")

      {:agent_surrender, filename, error} ->
        IO.puts("\n❌ Project failed: Max retries exceeded for #{filename}")
        IO.puts("Error: #{error}")
        IO.puts("\nThe Writer agent was unable to fix the issue after multiple attempts.")

        IO.puts(
          "Please check the manifest at /tmp/atelier_studio/#{project_id}/MANIFEST.md for details."
        )

      {:project_update, %{status: :completed}} ->
        IO.puts("\n✅ Project completed successfully!")

      {:project_update, %{status: :failed, error: reason}} ->
        IO.puts("\n❌ Project failed: #{reason}")

      {:execution_success, output} ->
        IO.puts("\n🚀 --- RUNTIME OUTPUT ---")
        IO.puts(IO.ANSI.green() <> output <> IO.ANSI.reset())
        wait_for_completion(project_id)

      {:execution_failure, output} ->
        IO.puts("\n💥 --- RUNTIME CRASH ---")
        IO.puts(IO.ANSI.red() <> output <> IO.ANSI.reset())
        wait_for_completion(project_id)

      {:project_update, _update} ->
        # Log other updates if necessary, or just keep waiting
        wait_for_completion(project_id)
    end
  end
end
