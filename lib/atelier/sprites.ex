defmodule Atelier.Sprites do
  @moduledoc """
  Client for Sprites.dev sandboxed execution environments.

  Sprites provides hardware-isolated Linux VMs for running untrusted code safely.
  Each Atelier project can have its own Sprite with persistent state and checkpoints.

  ## Configuration

  Set the `SPRITES_TOKEN` environment variable or configure in config.exs:

      config :atelier, Atelier.Sprites,
        token: "your-token",
        enabled: true

  ## Usage

      # Create a sprite for a project
      {:ok, sprite} = Sprites.create("my-project")

      # Write a file to the sprite
      :ok = Sprites.write_file("my-project", "main.py", "print('hello')")

      # Execute code
      {:ok, output} = Sprites.exec("my-project", "python3 main.py")

      # Checkpoint for later restore
      {:ok, checkpoint_id} = Sprites.checkpoint("my-project")
  """

  require Logger

  @base_url "https://api.sprites.dev/v1"
  @timeout 30_000

  @type sprite_name :: String.t()
  @type exec_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  Check if Sprites integration is enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:atelier, __MODULE__, [])[:enabled] == true
  end

  @doc """
  Create a new Sprite for a project.
  """
  @spec create(sprite_name()) :: {:ok, map()} | {:error, term()}
  def create(name) do
    Logger.info("Creating sprite", sprite: name)

    case request(:put, "/sprites/#{name}") do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        Logger.info("Sprite created successfully", sprite: name, status: status)
        {:ok, body}

      {:ok, %{status: 409}} ->
        # Already exists, that's fine
        Logger.debug("Sprite already exists", sprite: name)
        {:ok, %{"name" => name, "status" => "exists"}}

      {:ok, %{status: 401, body: body}} ->
        Logger.error("Sprite authentication failed - check SPRITES_TOKEN",
          sprite: name,
          status: 401,
          error: inspect(body)
        )
        {:error, {:auth_failed, body}}

      {:ok, %{status: 403, body: body}} ->
        Logger.error("Sprite access forbidden - token may lack permissions",
          sprite: name,
          status: 403,
          error: inspect(body)
        )
        {:error, {:forbidden, body}}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to create sprite",
          sprite: name,
          status: status,
          response: inspect(body)
        )
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to create sprite - network error",
          sprite: name,
          error: inspect(reason)
        )
        {:error, reason}
    end
  end

  @doc """
  Delete a Sprite.
  """
  @spec delete(sprite_name()) :: :ok | {:error, term()}
  def delete(name) do
    Logger.info("Deleting sprite", sprite: name)

    case request(:delete, "/sprites/#{name}") do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("Sprite deleted", sprite: name)
        :ok

      {:ok, %{status: 404}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Execute a command in a Sprite.

  Returns `{:ok, output}` on success (exit code 0) or
  `{:error, {:execution_failed, exit_code, output}}` on failure.
  """
  @spec exec(sprite_name(), String.t(), Keyword.t()) :: exec_result()
  def exec(name, command, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @timeout)
    Logger.debug("Executing command in sprite", sprite: name, command: String.slice(command, 0, 100))

    body = %{command: command}

    case request(:post, "/sprites/#{name}/exec", json: body, receive_timeout: timeout) do
      {:ok, %{status: 200, body: %{"exit_code" => 0, "output" => output}}} ->
        Logger.debug("Command succeeded", sprite: name, output_size: byte_size(output))
        {:ok, output}

      {:ok, %{status: 200, body: %{"exit_code" => code, "output" => output}}} ->
        Logger.debug("Command failed", sprite: name, exit_code: code, output: String.slice(output, 0, 200))
        {:error, {:execution_failed, code, output}}

      {:ok, %{status: 401, body: body}} ->
        Logger.error("Sprite exec auth failed", sprite: name, error: inspect(body))
        {:error, {:http_error, 401, body}}

      {:ok, %{status: 404, body: body}} ->
        Logger.error("Sprite not found - may not exist or not be started", sprite: name)
        {:error, {:sprite_not_found, body}}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Sprite exec failed", sprite: name, status: status, response: inspect(body))
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("Sprite exec network error", sprite: name, error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Write a file to a Sprite's filesystem.
  """
  @spec write_file(sprite_name(), String.t(), String.t()) :: :ok | {:error, term()}
  def write_file(name, path, content) do
    Logger.debug("Writing file to sprite", sprite: name, path: path, size: byte_size(content))

    # Use heredoc to write file content via exec
    # Escape any single quotes in content
    escaped = String.replace(content, "'", "'\\''")

    # Ensure parent directory exists
    dir = Path.dirname(path)
    mkdir_cmd = if dir != ".", do: "mkdir -p '#{dir}' && ", else: ""

    command = "#{mkdir_cmd}cat > '#{path}' << 'ATELIER_EOF'\n#{escaped}\nATELIER_EOF"

    case exec(name, command) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Read a file from a Sprite's filesystem.
  """
  @spec read_file(sprite_name(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def read_file(name, path) do
    case exec(name, "cat '#{path}'") do
      {:ok, content} -> {:ok, content}
      {:error, {:execution_failed, _, output}} -> {:error, {:file_error, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Initialize a project workspace in a Sprite.
  Sets up git and working directory.
  """
  @spec init_workspace(sprite_name()) :: {:ok, String.t()} | {:error, term()}
  def init_workspace(name) do
    workspace = "/workspace"

    commands = """
    mkdir -p #{workspace} && \
    cd #{workspace} && \
    git init && \
    git config user.name 'Atelier Bot' && \
    git config user.email 'bot@atelier.local' && \
    echo '#{workspace}'
    """

    case exec(name, commands) do
      {:ok, output} ->
        path = String.trim(output)
        Logger.info("Workspace initialized in sprite", sprite: name, path: path)
        {:ok, path}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a checkpoint of the current Sprite state.
  """
  @spec checkpoint(sprite_name(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def checkpoint(name, label \\ nil) do
    Logger.info("Creating checkpoint", sprite: name, label: label)

    body = if label, do: %{label: label}, else: %{}

    case request(:post, "/sprites/#{name}/checkpoint", json: body) do
      {:ok, %{status: status, body: %{"id" => id}}} when status in 200..299 ->
        Logger.info("Checkpoint created", sprite: name, checkpoint_id: id)
        {:ok, id}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Restore a Sprite to a previous checkpoint.
  """
  @spec restore(sprite_name(), String.t()) :: :ok | {:error, term()}
  def restore(name, checkpoint_id) do
    Logger.info("Restoring checkpoint", sprite: name, checkpoint_id: checkpoint_id)

    case request(:post, "/sprites/#{name}/restore", json: %{checkpoint_id: checkpoint_id}) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("Checkpoint restored", sprite: name)
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the public URL for a Sprite (if HTTP access is enabled).
  """
  @spec get_url(sprite_name()) :: {:ok, String.t()} | {:error, term()}
  def get_url(name) do
    case request(:get, "/sprites/#{name}") do
      {:ok, %{status: 200, body: %{"url" => url}}} ->
        {:ok, url}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  defp request(method, path, opts \\ []) do
    url = @base_url <> path

    opts =
      opts
      |> Keyword.put(:auth, {:bearer, token()})
      |> Keyword.put_new(:receive_timeout, @timeout)

    case method do
      :get -> Req.get(url, opts)
      :put -> Req.put(url, opts)
      :post -> Req.post(url, opts)
      :delete -> Req.delete(url, opts)
    end
  end

  defp token do
    case Application.get_env(:atelier, __MODULE__, [])[:token] do
      nil ->
        raise """
        SPRITES_TOKEN not configured.

        Add to .env file: SPRITES_TOKEN=org/account-id/token-id/token-value
        """

      token when byte_size(token) < 50 ->
        Logger.warning("SPRITES_TOKEN appears truncated (#{String.length(token)} chars)")
        token

      token ->
        token
    end
  end
end
