defmodule Atelier.Studio do
  def start_project(project_id) do
    # Add Architect, Writer, and Auditor
    roles = [:architect, :writer, :auditor, :clerk, :validator]

    Enum.each(roles, fn role ->
      DynamicSupervisor.start_child(
        Atelier.AgentSupervisor,
        {Atelier.Agent, [role: role, project_id: project_id]}
      )
    end)

    :ok
  end

  def request_feature(project_id, requirement) do
    pid = GenServer.whereis({:global, {project_id, :architect}})
    GenServer.cast(pid, {:design_spec, requirement})
  end
end
