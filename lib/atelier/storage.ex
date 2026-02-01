defmodule Atelier.Storage do
  require Logger
  # Use Path.expand to ensure we are working with an absolute path
  # based on where the project root is.
  @storage_root Path.expand("/tmp/atelier_studio")

  def write_file(project_id, filename, content) do
    # 1. Define the directory for the project
    project_dir = Path.join(@storage_root, project_id)

    # 2. Ensure the directory exists (creates /tmp/atelier_studio/project_id)
    File.mkdir_p!(project_dir)

    # 3. Write the file
    path = Path.join(project_dir, filename)

    # 4. Ensure parent directory exists for files in subdirectories
    path |> Path.dirname() |> File.mkdir_p!()

    Logger.debug("Writing file",
      project_id: project_id,
      filename: filename,
      content_size: byte_size(content)
    )

    File.write!(path, content)
    Logger.debug("File written successfully", path: path)

    {:ok, path}
  end

  def read_file(project_id, filename) do
    path = Path.join([@storage_root, project_id, filename])
    Logger.debug("Reading file", project_id: project_id, filename: filename, path: path)
    File.read(path)
  end

  def init_workspace(project_id) do
    path = Path.expand("/tmp/atelier_studio/#{project_id}")
    Logger.info("Initializing workspace", project_id: project_id, path: path)
    File.mkdir_p!(path)

    # Initialize git if it's not already there
    if !File.dir?(Path.join(path, ".git")) do
      Logger.debug("Initializing git repository", project_id: project_id, path: path)
      {init_output, init_status} = System.cmd("git", ["init"], cd: path)

      if init_status == 0 do
        Logger.debug("Git repository initialized")
        System.cmd("git", ["config", "user.name", "Atelier Bot"], cd: path)
        System.cmd("git", ["config", "user.email", "bot@atelier.local"], cd: path)
        Logger.debug("Git user configured")
      else
        Logger.error("Failed to initialize git repository", output: init_output)
      end
    else
      Logger.debug("Git repository already exists", project_id: project_id)
    end

    path
  end
end
