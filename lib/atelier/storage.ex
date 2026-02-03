defmodule Atelier.Storage do
  @moduledoc """
  File storage for Atelier projects.

  Supports two storage backends:
  - Local: Files stored in `/tmp/atelier_studio/{project_id}/`
  - Sprites: Files stored in isolated sandbox at `/workspace/`

  The backend is selected based on `Atelier.Sprites.enabled?()`.
  """

  require Logger

  alias Atelier.Sprites

  @storage_root Path.expand("/tmp/atelier_studio")

  @doc """
  Write a file to the project workspace.
  """
  @spec write_file(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def write_file(project_id, filename, content) do
    Logger.debug("Writing file",
      project_id: project_id,
      filename: filename,
      content_size: byte_size(content),
      sandbox: Sprites.enabled?()
    )

    if Sprites.enabled?() do
      write_file_sprite(project_id, filename, content)
    else
      write_file_local(project_id, filename, content)
    end
  end

  @doc """
  Read a file from the project workspace.
  """
  @spec read_file(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def read_file(project_id, filename) do
    Logger.debug("Reading file",
      project_id: project_id,
      filename: filename,
      sandbox: Sprites.enabled?()
    )

    if Sprites.enabled?() do
      read_file_sprite(project_id, filename)
    else
      read_file_local(project_id, filename)
    end
  end

  @doc """
  Initialize the project workspace.
  Creates the directory structure and initializes git.
  """
  @spec init_workspace(String.t()) :: String.t() | {:ok, String.t()} | {:error, term()}
  def init_workspace(project_id) do
    Logger.info("Initializing workspace",
      project_id: project_id,
      sandbox: Sprites.enabled?()
    )

    if Sprites.enabled?() do
      init_workspace_sprite(project_id)
    else
      init_workspace_local(project_id)
    end
  end

  @doc """
  Get the workspace path for a project.
  """
  @spec workspace_path(String.t()) :: String.t()
  def workspace_path(project_id) do
    if Sprites.enabled?() do
      "/workspace"
    else
      Path.join(@storage_root, project_id)
    end
  end

  # Local storage implementation

  defp write_file_local(project_id, filename, content) do
    project_dir = Path.join(@storage_root, project_id)
    File.mkdir_p!(project_dir)

    path = Path.join(project_dir, filename)
    path |> Path.dirname() |> File.mkdir_p!()

    File.write!(path, content)
    Logger.debug("File written locally", path: path)

    {:ok, path}
  end

  defp read_file_local(project_id, filename) do
    path = Path.join([@storage_root, project_id, filename])
    File.read(path)
  end

  defp init_workspace_local(project_id) do
    path = Path.join(@storage_root, project_id)
    File.mkdir_p!(path)

    unless File.dir?(Path.join(path, ".git")) do
      Logger.debug("Initializing git repository", project_id: project_id, path: path)
      {_output, status} = System.cmd("git", ["init"], cd: path)

      if status == 0 do
        System.cmd("git", ["config", "user.name", "Atelier Bot"], cd: path)
        System.cmd("git", ["config", "user.email", "bot@atelier.local"], cd: path)
        Logger.debug("Git repository initialized")
      end
    end

    path
  end

  # Sprites sandbox implementation

  defp write_file_sprite(project_id, filename, content) do
    sprite_name = sprite_name(project_id)
    path = "/workspace/#{filename}"

    case Sprites.write_file(sprite_name, path, content) do
      :ok ->
        Logger.debug("File written to sprite", sprite: sprite_name, path: path)
        {:ok, path}

      {:error, {:http_error, 401, _}} = error ->
        Logger.error("Sprite write failed: authentication error",
          sprite: sprite_name,
          path: path,
          hint: "Check SPRITES_TOKEN in .env file"
        )
        error

      {:error, {:sprite_not_found, _}} = error ->
        Logger.error("Sprite write failed: sprite not found",
          sprite: sprite_name,
          path: path,
          hint: "Sprite may not have been created - check Environment agent health check"
        )
        error

      {:error, reason} = error ->
        Logger.error("Failed to write file to sprite",
          sprite: sprite_name,
          path: path,
          error: inspect(reason)
        )
        error
    end
  end

  defp read_file_sprite(project_id, filename) do
    sprite_name = sprite_name(project_id)
    path = "/workspace/#{filename}"

    case Sprites.read_file(sprite_name, path) do
      {:ok, content} ->
        Logger.debug("File read from sprite", sprite: sprite_name, path: path, size: byte_size(content))
        {:ok, content}

      {:error, {:file_error, output}} = error ->
        Logger.error("Sprite read failed: file not found",
          sprite: sprite_name,
          path: path,
          output: output
        )
        error

      {:error, reason} = error ->
        Logger.error("Failed to read file from sprite",
          sprite: sprite_name,
          path: path,
          error: inspect(reason)
        )
        error
    end
  end

  defp init_workspace_sprite(project_id) do
    sprite_name = sprite_name(project_id)
    Logger.info("Creating sprite for project", sprite: sprite_name, project_id: project_id)

    # Create the sprite first
    case Sprites.create(sprite_name) do
      {:ok, _} ->
        Logger.info("Sprite created, initializing workspace", sprite: sprite_name)
        # Initialize workspace inside the sprite
        case Sprites.init_workspace(sprite_name) do
          {:ok, path} ->
            Logger.info("Sprite workspace initialized", sprite: sprite_name, path: path)
            path

          {:error, reason} ->
            Logger.error("Failed to initialize sprite workspace",
              sprite: sprite_name,
              error: inspect(reason)
            )
            {:error, reason}
        end

      {:error, {:auth_failed, _}} = error ->
        Logger.error("Sprite creation failed: authentication error",
          sprite: sprite_name,
          hint: "Check SPRITES_TOKEN in .env file"
        )
        error

      {:error, reason} ->
        Logger.error("Failed to create sprite",
          sprite: sprite_name,
          error: inspect(reason)
        )
        {:error, reason}
    end
  end

  defp sprite_name(project_id), do: "atelier-#{project_id}"
end
