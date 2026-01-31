defmodule Atelier.Agent do
  @moduledoc """
  GenServer delegator that routes agent behavior to specialized implementation modules.
  """

  use GenServer
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

    IO.puts("✨ Agent [#{role}] joined Atelier for #{project_id}")

    # Map roles to their specific implementation modules
    module =
      case role do
        :architect -> Atelier.Agents.Architect
        :writer -> Atelier.Agents.Writer
        :auditor -> Atelier.Agents.Auditor
        :validator -> Atelier.Agents.Validator
        :git_bot -> Atelier.Agents.GitBot
        :clerk -> Atelier.Agents.Clerk
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
    state.module.handle_cast(msg, state)
  end

  # Delegate all infos to the role-specific module
  @impl true
  def handle_info(msg, state) do
    state.module.handle_info(msg, state)
  end
end
