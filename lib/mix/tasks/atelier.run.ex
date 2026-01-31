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
    Atelier.Studio.request_feature(project_id, requirement)

    Logger.info("🚀 Studio started for: #{project_id}")

    # 4. Wait for the 'project_finished' message
    wait_for_completion()
  end

  defp wait_for_completion do
    receive do
      :project_finished ->
        IO.puts("\n🎉 All agents have finished their work. Check the 'tmp' folder.")

      {:llm_error, reason} ->
        IO.puts("\n❌ Error: #{reason}")

      _ ->
        wait_for_completion()
    end
  end
end
