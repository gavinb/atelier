defmodule Atelier.Storage do
  @storage_root "tmp/atelier_studio"

  def init_workspace(project_id) do
    path = Path.join(@storage_root, project_id)
    File.mkdir_p!(path)
    path
  end

  def write_file(project_id, filename, content) do
    path = Path.join([@storage_root, project_id, filename])
    File.write!(path, content)
    {:ok, path}
  end

  def read_file(project_id, filename) do
    Path.join([@storage_root, project_id, filename]) |> File.read()
  end
end
