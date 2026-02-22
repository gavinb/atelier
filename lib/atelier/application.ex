defmodule Atelier.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = base_children() ++ dashboard_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Atelier.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp base_children do
    [
      # 1. The message bus for our Agents
      {Phoenix.PubSub, name: Atelier.PubSub},

      # 2. A DynamicSupervisor to spin up/down Agent teams on demand
      {DynamicSupervisor, name: Atelier.AgentSupervisor, strategy: :one_for_one},

      # 3. Task supervisor for async LLM calls
      {Task.Supervisor, name: Atelier.LLMTaskSupervisor},

      # 4. Dashboard event collector (always running to track events)
      Atelier.Dashboard.EventCollector
    ]
  end

  defp dashboard_children do
    if Application.get_env(:atelier, :start_dashboard, false) do
      [AtelierWeb.Endpoint]
    else
      []
    end
  end
end
