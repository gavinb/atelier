defmodule Atelier.Dashboard.EventCollector do
  @moduledoc """
  Collects and buffers events from all Atelier projects for the dashboard.

  Subscribes to project topics and maintains state for:
  - Active projects and their status
  - Recent events (buffered for display)
  - Agent states per project
  - File progress tracking
  """

  use GenServer
  require Logger

  @max_events 100

  # Client API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec register_project(String.t()) :: :ok
  def register_project(project_id) do
    GenServer.cast(__MODULE__, {:register_project, project_id})
  end

  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @spec get_projects() :: map()
  def get_projects do
    GenServer.call(__MODULE__, :get_projects)
  end

  @spec get_events(non_neg_integer()) :: list()
  def get_events(limit \\ 50) do
    GenServer.call(__MODULE__, {:get_events, limit})
  end

  @spec subscribe() :: :ok
  def subscribe do
    Phoenix.PubSub.subscribe(Atelier.PubSub, "dashboard:events")
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      projects: %{},
      events: [],
      started_at: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:register_project, project_id}, state) do
    # Subscribe to this project's topic
    Phoenix.PubSub.subscribe(Atelier.PubSub, "project:#{project_id}")

    project_state = %{
      id: project_id,
      status: :starting,
      agents: %{},
      files: %{},
      started_at: DateTime.utc_now(),
      finished_at: nil
    }

    new_state = put_in(state, [:projects, project_id], project_state)
    broadcast_update(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_projects, _from, state) do
    {:reply, state.projects, state}
  end

  def handle_call({:get_events, limit}, _from, state) do
    events = Enum.take(state.events, limit)
    {:reply, events, state}
  end

  # Handle PubSub messages from projects
  @impl true
  def handle_info({:blueprint_ready, files}, state) do
    project_id = get_current_project(state)
    event = build_event(:blueprint_ready, project_id, %{file_count: length(files)})

    new_state =
      state
      |> add_event(event)
      |> update_project(project_id, fn p ->
        file_map =
          Enum.reduce(files, %{}, fn %{"name" => name}, acc ->
            Map.put(acc, name, %{status: :pending, started_at: nil, finished_at: nil})
          end)

        %{p | status: :in_progress, files: file_map}
      end)

    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_info({:code_ready, _code, filename}, state) do
    project_id = get_current_project(state)
    event = build_event(:code_ready, project_id, %{filename: filename})

    new_state =
      state
      |> add_event(event)
      |> update_file_status(project_id, filename, :validating)

    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_info({:validation_passed, filename}, state) do
    project_id = get_current_project(state)
    event = build_event(:validation_passed, project_id, %{filename: filename})

    new_state =
      state
      |> add_event(event)
      |> update_file_status(project_id, filename, :validated)

    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_info({:validation_failed, filename, error}, state) do
    project_id = get_current_project(state)
    event = build_event(:validation_failed, project_id, %{filename: filename, error: error})

    new_state =
      state
      |> add_event(event)
      |> update_file_status(project_id, filename, :failed)

    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_info({:file_validated, filename}, state) do
    project_id = get_current_project(state)
    event = build_event(:file_validated, project_id, %{filename: filename})

    new_state =
      state
      |> add_event(event)
      |> update_file_status(project_id, filename, :committed)

    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_info({:execution_success, filename, _output}, state) do
    project_id = get_current_project(state)
    event = build_event(:execution_success, project_id, %{filename: filename})

    new_state = add_event(state, event)
    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_info({:execution_failure, filename, _output}, state) do
    project_id = get_current_project(state)
    event = build_event(:execution_failure, project_id, %{filename: filename})

    new_state = add_event(state, event)
    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_info({:agent_surrender, filename, _error}, state) do
    project_id = get_current_project(state)
    event = build_event(:agent_surrender, project_id, %{filename: filename})

    new_state =
      state
      |> add_event(event)
      |> update_project(project_id, fn p -> %{p | status: :failed} end)

    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_info(:project_finished, state) do
    project_id = get_current_project(state)
    event = build_event(:project_finished, project_id, %{})

    new_state =
      state
      |> add_event(event)
      |> update_project(project_id, fn p ->
        %{p | status: :completed, finished_at: DateTime.utc_now()}
      end)

    broadcast_update(new_state)
    {:noreply, new_state}
  end

  # Catch-all for other messages
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private helpers

  defp get_current_project(state) do
    # Return the most recently started active project
    state.projects
    |> Enum.filter(fn {_id, p} -> p.status in [:starting, :in_progress] end)
    |> Enum.sort_by(fn {_id, p} -> p.started_at end, {:desc, DateTime})
    |> List.first()
    |> case do
      {id, _project} -> id
      nil -> "unknown"
    end
  end

  defp build_event(type, project_id, data) do
    %{
      id: System.unique_integer([:positive]),
      type: type,
      project_id: project_id,
      data: data,
      timestamp: DateTime.utc_now()
    }
  end

  defp add_event(state, event) do
    events = [event | state.events] |> Enum.take(@max_events)
    %{state | events: events}
  end

  defp update_project(state, project_id, fun) do
    case get_in(state, [:projects, project_id]) do
      nil -> state
      project -> put_in(state, [:projects, project_id], fun.(project))
    end
  end

  defp update_file_status(state, project_id, filename, status) do
    update_project(state, project_id, fn p ->
      files =
        Map.update(p.files, filename, %{status: status}, fn f ->
          %{f | status: status}
        end)

      %{p | files: files}
    end)
  end

  defp broadcast_update(state) do
    Phoenix.PubSub.broadcast(Atelier.PubSub, "dashboard:events", {:dashboard_update, state})
  end
end
