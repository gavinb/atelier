defmodule Atelier.Studio do
  require Logger

  def start_project(project_id) do
    # Initialize workspace with git repository before starting agents
    Atelier.Storage.init_workspace(project_id)

    # Register with dashboard event collector
    Atelier.Dashboard.EventCollector.register_project(project_id)

    roles = [
      :environment,
      :architect,
      :writer,
      :auditor,
      :clerk,
      :validator,
      :git_bot,
      :runner,
      :analyst,
      :researcher
    ]

    Logger.info("Starting project", project_id: project_id, agent_count: length(roles))

    Enum.each(roles, fn role ->
      Logger.debug("Starting agent", role: role, project_id: project_id)

      case DynamicSupervisor.start_child(
             Atelier.AgentSupervisor,
             {Atelier.Agent, [role: role, project_id: project_id]}
           ) do
        {:ok, _pid} ->
          Logger.debug("Agent started successfully", role: role)

        {:error, reason} ->
          Logger.error("Failed to start agent", role: role, reason: inspect(reason))
      end
    end)

    Logger.info("Project startup complete", project_id: project_id)
    :ok
  end

  def request_feature(project_id, requirement) do
    Logger.info("Feature request received",
      project_id: project_id,
      requirement_length: String.length(requirement)
    )

    pid = GenServer.whereis({:global, {project_id, :architect}})

    if pid do
      Logger.debug("Sending design spec to architect", project_id: project_id)
      GenServer.cast(pid, {:design_spec, requirement})
    else
      Logger.error("Architect process not found", project_id: project_id)
    end
  end
end
