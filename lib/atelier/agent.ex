defmodule Atelier.Agent do
  @moduledoc """
  GenServer delegator that routes agent behavior to specialized implementation modules.
  """

  use GenServer
  require Logger
  alias Phoenix.PubSub

  def start_link(opts) do
    name = {:global, {opts[:project_id], opts[:role]}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    role = opts[:role]
    project_id = opts[:project_id]
    topic = "project:#{project_id}"
    PubSub.subscribe(Atelier.PubSub, topic)

    Logger.info("Agent initialized", role: role, project_id: project_id)
    IO.puts("✨ Agent [#{role}] joined Atelier for #{project_id}")

    # Map roles to their specific implementation modules
    module =
      case role do
        :environment ->
          Logger.debug("Mapping role to Environment implementation")
          Atelier.Agents.Environment
        :architect ->
          Logger.debug("Mapping role to Architect implementation")
          Atelier.Agents.Architect
        :writer ->
          Logger.debug("Mapping role to Writer implementation")
          Atelier.Agents.Writer
        :auditor ->
          Logger.debug("Mapping role to Auditor implementation")
          Atelier.Agents.Auditor
        :validator ->
          Logger.debug("Mapping role to Validator implementation")
          Atelier.Agents.Validator
        :git_bot ->
          Logger.debug("Mapping role to GitBot implementation")
          Atelier.Agents.GitBot
        :clerk ->
          Logger.debug("Mapping role to Clerk implementation")
          Atelier.Agents.Clerk
      end

    {:ok,
     %{
       role: role,
       project_id: project_id,
       topic: topic,
       module: module,
       memory: []
     }}
  end

  # Delegate all casts to the role-specific module
  @impl true
  def handle_cast(msg, state) do
    message_type = if is_tuple(msg), do: elem(msg, 0), else: msg
    Logger.debug("Delegating cast message", role: state.role, message_type: message_type)
    state.module.handle_cast(msg, state)
  end

  # Delegate all infos to the role-specific module
  @impl true
  def handle_info(msg, state) do
    message_type = if is_tuple(msg), do: elem(msg, 0), else: msg
    Logger.debug("Delegating info message", role: state.role, message_type: message_type)
    state.module.handle_info(msg, state)
  end
end
