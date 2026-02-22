defmodule Atelier.Storage do
  @moduledoc """
  File storage for Atelier projects.

  Supports two storage backends:
  - Local: Files stored in `/tmp/atelier_studio/{project_id}/`
  - Sprites: Files stored in isolated sandbox at `/workspace/`

  The backend is selected based on config `:atelier, :sprites, :enabled`.
  """

  require Logger

  @storage_root Path.expand("/tmp/atelier_studio")
  @workspace_path "/workspace"

  @doc """
  Write a file to the project workspace.
  """
  @spec write_file(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def write_file(project_id, filename, content) do
    sandbox = sprites_enabled?()

    Logger.debug("Writing file",
      project_id: project_id,
      filename: filename,
      content_size: byte_size(content),
      sandbox: sandbox
    )

    if sandbox do
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
    sandbox = sprites_enabled?()

    Logger.debug("Reading file",
      project_id: project_id,
      filename: filename,
      sandbox: sandbox
    )

    if sandbox do
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
    sandbox = sprites_enabled?()

    Logger.info("Initializing workspace",
      project_id: project_id,
      sandbox: sandbox
    )

    if sandbox do
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
    if sprites_enabled?() do
      @workspace_path
    else
      Path.join(@storage_root, project_id)
    end
  end

  @doc """
  Check if Sprites integration is enabled.
  """
  @spec sprites_enabled?() :: boolean()
  def sprites_enabled? do
    Application.get_env(:atelier, :sprites, [])[:enabled] == true
  end

  @doc """
  Get a Sprites client. Returns nil if not enabled or token not configured.
  """
  @spec sprites_client() :: Sprites.client() | nil
  def sprites_client do
    if sprites_enabled?() do
      case Application.get_env(:atelier, :sprites, [])[:token] do
        nil -> nil
        token -> Sprites.new(token)
      end
    end
  end

  @doc """
  Get a sprite handle for a project.
  """
  @spec get_sprite(String.t()) :: Sprites.sprite() | nil
  def get_sprite(project_id) do
    case sprites_client() do
      nil -> nil
      client -> Sprites.sprite(client, sprite_name(project_id))
    end
  end

  @doc """
  Get a filesystem handle for a project's workspace.
  """
  @spec get_filesystem(String.t()) :: Sprites.Filesystem.t() | nil
  def get_filesystem(project_id) do
    case get_sprite(project_id) do
      nil -> nil
      sprite -> Sprites.filesystem(sprite, @workspace_path)
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

    git_dir = Path.join(path, ".git")

    unless File.dir?(git_dir) do
      Logger.debug("Initializing git repository", project_id: project_id, path: path)
      {_output, status} = System.cmd("git", ["init"], cd: path, env: [])

      if status == 0 do
        System.cmd("git", ["config", "user.name", "Atelier Bot"], cd: path, env: [])
        System.cmd("git", ["config", "user.email", "bot@atelier.local"], cd: path, env: [])
        Logger.debug("Git repository initialized")
      end
    end

    path
  end

  # Sprites sandbox implementation using official SDK

  defp write_file_sprite(project_id, filename, content) do
    case get_filesystem(project_id) do
      nil ->
        {:error, :sprites_not_configured}

      fs ->
        path = filename

        case Sprites.Filesystem.write(fs, path, content) do
          :ok ->
            full_path = Path.join(@workspace_path, filename)

            Logger.debug("File written to sprite",
              sprite: sprite_name(project_id),
              path: full_path
            )

            {:ok, full_path}

          {:error, reason} = error ->
            Logger.error("Failed to write file to sprite",
              sprite: sprite_name(project_id),
              path: path,
              error: inspect(reason)
            )

            error
        end
    end
  end

  defp read_file_sprite(project_id, filename) do
    case get_filesystem(project_id) do
      nil ->
        {:error, :sprites_not_configured}

      fs ->
        case Sprites.Filesystem.read(fs, filename) do
          {:ok, content} ->
            Logger.debug("File read from sprite",
              sprite: sprite_name(project_id),
              path: filename,
              size: byte_size(content)
            )

            {:ok, content}

          {:error, :enoent} = error ->
            Logger.error("Sprite read failed: file not found",
              sprite: sprite_name(project_id),
              path: filename
            )

            error

          {:error, reason} = error ->
            Logger.error("Failed to read file from sprite",
              sprite: sprite_name(project_id),
              path: filename,
              error: inspect(reason)
            )

            error
        end
    end
  end

  defp init_workspace_sprite(project_id) do
    sprite_name = sprite_name(project_id)
    Logger.info("Creating sprite for project", sprite: sprite_name, project_id: project_id)

    case sprites_client() do
      nil ->
        {:error, :sprites_not_configured}

      client ->
        # Create the sprite
        case Sprites.create(client, sprite_name) do
          {:ok, sprite} ->
            Logger.info("Sprite created, initializing workspace", sprite: sprite_name)
            init_git_in_sprite(sprite)

          {:error, reason} ->
            Logger.error("Failed to create sprite",
              sprite: sprite_name,
              error: inspect(reason)
            )

            {:error, reason}
        end
    end
  end

  defp init_git_in_sprite(sprite) do
    commands = """
    mkdir -p #{@workspace_path} && \
    cd #{@workspace_path} && \
    git init && \
    git config user.name 'Atelier Bot' && \
    git config user.email 'bot@atelier.local'
    """

    case Sprites.cmd(sprite, "sh", ["-c", commands]) do
      {_output, 0} ->
        Logger.info("Sprite workspace initialized", path: @workspace_path)
        @workspace_path

      {output, code} ->
        Logger.error("Failed to initialize sprite workspace",
          exit_code: code,
          output: output
        )

        {:error, {:init_failed, code, output}}
    end
  end

  defp sprite_name(project_id), do: "atelier-#{project_id}"
end
