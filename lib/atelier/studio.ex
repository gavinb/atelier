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

  def submit_work(project_id, filename, code) do
    # Find the writer for this specific project
    pid = GenServer.whereis({:global, {project_id, :writer}})

    if pid do
      # Pass both the filename and the code
      GenServer.cast(pid, {:write_code, filename, code})
    else
      {:error, :writer_not_found}
    end
  end
end
