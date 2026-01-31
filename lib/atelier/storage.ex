defmodule Atelier.Storage do
  # Use Path.expand to ensure we are working with an absolute path
  # based on where the project root is.
  @storage_root Path.expand("tmp/atelier_studio")

  def write_file(project_id, filename, content) do
    # 1. Define the directory for the project
    project_dir = Path.join(@storage_root, project_id)

    # 2. Ensure the directory exists (creates tmp/atelier_studio/project_id)
    File.mkdir_p!(project_dir)

    # 3. Write the file
    path = Path.join(project_dir, filename)
    File.write!(path, content)

    {:ok, path}
  end

  def read_file(project_id, filename) do
    Path.join([@storage_root, project_id, filename])
    |> File.read()
  end

  def init_workspace(project_id) do
    path = Path.expand("tmp/atelier_studio/#{project_id}")
    File.mkdir_p!(path)

    # Initialize git if it's not already there
    if !File.dir?(Path.join(path, ".git")) do
      System.cmd("git", ["init"], cd: path)
      System.cmd("git", ["config", "user.name", "Atelier Bot"], cd: path)
      System.cmd("git", ["config", "user.email", "bot@atelier.local"], cd: path)
    end

    path
  end
end
