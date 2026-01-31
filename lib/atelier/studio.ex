defmodule Atelier.Studio do
  def start_project(project_id) do
    # Add a Writer
    DynamicSupervisor.start_child(
      Atelier.AgentSupervisor,
      {Atelier.Agent, [role: :writer, project_id: project_id]}
    )

    # Add an Auditor
    DynamicSupervisor.start_child(
      Atelier.AgentSupervisor,
      {Atelier.Agent, [role: :auditor, project_id: project_id]}
    )

    :ok
  end

  def submit_work(project_id, code) do
    # Find the writer for this specific project and give them work
    pid = GenServer.whereis({:global, {project_id, :writer}})
    GenServer.cast(pid, {:write_code, code})
  end
end
