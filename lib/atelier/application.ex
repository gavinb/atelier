defmodule Atelier.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # 1. The message bus for our Agents
      {Phoenix.PubSub, name: Factory.PubSub},

      # 2. A DynamicSupervisor to spin up/down Agent teams on demand
      {DynamicSupervisor, name: Factory.AgentSupervisor, strategy: :one_for_one}

      # Starts a worker by calling: Atelier.Worker.start_link(arg)
      # {Atelier.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Atelier.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
