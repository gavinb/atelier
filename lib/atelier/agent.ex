defmodule Atelier.Agent.Worker do
  @moduledoc """
  Behaviour for role-specific agent implementation modules.
  """

  @callback init_state(opts :: Keyword.t()) :: map()
end

defmodule Atelier.Agent do
  @moduledoc """
  GenServer delegator that routes agent behavior to specialized implementation modules.
  """

  use GenServer

  alias Phoenix.PubSub

  require Logger

  @role_modules %{
    environment: Atelier.Agents.Environment,
    architect: Atelier.Agents.Architect,
    writer: Atelier.Agents.Writer,
    auditor: Atelier.Agents.Auditor,
    validator: Atelier.Agents.Validator,
    git_bot: Atelier.Agents.GitBot,
    clerk: Atelier.Agents.Clerk,
    runner: Atelier.Agents.Runner,
    analyst: Atelier.Agents.Analyst,
    researcher: Atelier.Agents.Researcher
  }

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    name = {:global, {opts[:project_id], opts[:role]}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    role = opts[:role]
    project_id = opts[:project_id]
    topic = "project:#{project_id}"
    PubSub.subscribe(Atelier.PubSub, topic)

    Logger.info("Agent initialized", role: role, project_id: project_id)
    IO.puts("✨ Agent [#{role}] joined Atelier for #{project_id}")

    module = Map.fetch!(@role_modules, role)
    Logger.debug("Mapping role to #{inspect(module)} implementation")

    initial_state = module.init_state(opts)
    state = Map.put(initial_state, :module, module)

    Logger.debug("Agent process started and state initialized.")

    {:ok, state}
  end

  # Delegate all casts to the role-specific module
  @impl GenServer
  def handle_cast(msg, state) do
    message_type = if is_tuple(msg), do: elem(msg, 0), else: msg
    Logger.debug("Delegating cast message", role: state.role, message_type: message_type)
    state.module.handle_cast(msg, state)
  end

  # Delegate all infos to the role-specific module
  @impl GenServer
  def handle_info(:project_finished, state) do
    # Let the module handle the message first (e.g., Clerk writes final manifest)
    case state.module.handle_info(:project_finished, state) do
      {:noreply, new_state} ->
        # Schedule shutdown after a brief delay to allow final operations
        Process.send_after(self(), :shutdown, 1000)
        {:noreply, new_state}

      other ->
        other
    end
  end

  def handle_info(:shutdown, state) do
    Logger.info("Agent shutting down", role: state.role, project_id: state.project_id)
    IO.puts("👋 Agent [#{state.role}] leaving Atelier for #{state.project_id}")
    {:stop, :normal, state}
  end

  def handle_info(msg, state) do
    message_type = if is_tuple(msg), do: elem(msg, 0), else: msg
    Logger.debug("Delegating info message", role: state.role, message_type: message_type)
    state.module.handle_info(msg, state)
  end
end
