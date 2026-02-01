defmodule AtelierWeb.DashboardLive do
  @moduledoc """
  LiveView dashboard for monitoring Atelier projects in real-time.
  """

  use AtelierWeb, :live_view

  alias Atelier.Dashboard.EventCollector

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EventCollector.subscribe()
    end

    state = EventCollector.get_state()

    {:ok,
     assign(socket,
       projects: state.projects,
       events: state.events,
       selected_project: nil
     )}
  end

  @impl true
  def handle_info({:dashboard_update, state}, socket) do
    {:noreply,
     assign(socket,
       projects: state.projects,
       events: state.events
     )}
  end

  @impl true
  def handle_event("select_project", %{"id" => project_id}, socket) do
    {:noreply, assign(socket, selected_project: project_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-gray-100">
      <!-- Header -->
      <header class="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <span class="text-2xl">🎨</span>
            <h1 class="text-xl font-semibold text-white">Atelier Dashboard</h1>
          </div>
          <div class="text-sm text-gray-400">
            {length(Map.keys(@projects))} project(s)
          </div>
        </div>
      </header>

      <div class="flex h-[calc(100vh-73px)]">
        <!-- Sidebar: Projects List -->
        <aside class="w-64 bg-gray-800 border-r border-gray-700 overflow-y-auto">
          <div class="p-4">
            <h2 class="text-sm font-medium text-gray-400 uppercase tracking-wider mb-3">
              Projects
            </h2>
            <%= if Enum.empty?(@projects) do %>
              <p class="text-sm text-gray-500 italic">No active projects</p>
              <p class="text-xs text-gray-600 mt-2">
                Start a project with:<br />
                <code class="text-green-400">Atelier.Studio.start_project("name")</code>
              </p>
            <% else %>
              <ul class="space-y-2">
                <%= for {id, project} <- @projects do %>
                  <li>
                    <button
                      phx-click="select_project"
                      phx-value-id={id}
                      class={"w-full text-left px-3 py-2 rounded-lg transition-colors #{if @selected_project == id, do: "bg-indigo-600 text-white", else: "bg-gray-700 hover:bg-gray-600 text-gray-200"}"}
                    >
                      <div class="flex items-center justify-between">
                        <span class="font-medium truncate">{id}</span>
                        <.status_badge status={project.status} />
                      </div>
                    </button>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </aside>

        <!-- Main Content -->
        <main class="flex-1 overflow-y-auto">
          <%= if @selected_project && @projects[@selected_project] do %>
            <.project_detail project={@projects[@selected_project]} events={@events} />
          <% else %>
            <.event_feed events={@events} />
          <% end %>
        </main>
      </div>
    </div>
    """
  end

  # Components

  defp status_badge(assigns) do
    {bg_class, text} =
      case assigns.status do
        :starting -> {"bg-yellow-500", "Starting"}
        :in_progress -> {"bg-blue-500", "Running"}
        :completed -> {"bg-green-500", "Done"}
        :failed -> {"bg-red-500", "Failed"}
        _ -> {"bg-gray-500", "Unknown"}
      end

    assigns = assign(assigns, bg_class: bg_class, text: text)

    ~H"""
    <span class={"text-xs px-2 py-0.5 rounded-full #{@bg_class} text-white"}>
      {@text}
    </span>
    """
  end

  defp project_detail(assigns) do
    ~H"""
    <div class="p-6">
      <!-- Project Header -->
      <div class="mb-6">
        <h2 class="text-2xl font-bold text-white">{@project.id}</h2>
        <div class="flex items-center gap-4 mt-2 text-sm text-gray-400">
          <span>Started: {format_time(@project.started_at)}</span>
          <%= if @project.finished_at do %>
            <span>Finished: {format_time(@project.finished_at)}</span>
          <% end %>
        </div>
      </div>

      <!-- File Progress -->
      <div class="bg-gray-800 rounded-lg p-4 mb-6">
        <h3 class="text-lg font-medium text-white mb-4">📁 Files</h3>
        <%= if Enum.empty?(@project.files) do %>
          <p class="text-gray-500 italic">Waiting for blueprint...</p>
        <% else %>
          <div class="space-y-2">
            <%= for {filename, file} <- @project.files do %>
              <div class="flex items-center justify-between bg-gray-700 rounded px-3 py-2">
                <span class="font-mono text-sm text-gray-200">{filename}</span>
                <.file_status_badge status={file.status} />
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Project Events -->
      <div class="bg-gray-800 rounded-lg p-4">
        <h3 class="text-lg font-medium text-white mb-4">📋 Events</h3>
        <.event_list events={Enum.filter(@events, & &1.project_id == @project.id)} />
      </div>
    </div>
    """
  end

  defp event_feed(assigns) do
    ~H"""
    <div class="p-6">
      <h2 class="text-xl font-bold text-white mb-4">📡 Live Event Feed</h2>
      <p class="text-gray-400 mb-6">
        Showing all events across projects. Select a project to filter.
      </p>
      <.event_list events={@events} />
    </div>
    """
  end

  defp event_list(assigns) do
    ~H"""
    <%= if Enum.empty?(@events) do %>
      <p class="text-gray-500 italic">No events yet</p>
    <% else %>
      <div class="space-y-2 max-h-96 overflow-y-auto">
        <%= for event <- @events do %>
          <div class="flex items-start gap-3 bg-gray-700/50 rounded px-3 py-2">
            <span class="text-lg">{event_icon(event.type)}</span>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="font-medium text-gray-200">{event_label(event.type)}</span>
                <span class="text-xs text-gray-500">{format_time(event.timestamp)}</span>
              </div>
              <div class="text-sm text-gray-400 truncate">
                {event_description(event)}
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp file_status_badge(assigns) do
    {bg_class, icon, text} =
      case assigns.status do
        :pending -> {"bg-gray-600", "⏳", "Pending"}
        :validating -> {"bg-yellow-600", "🔄", "Validating"}
        :validated -> {"bg-blue-600", "✓", "Validated"}
        :committed -> {"bg-green-600", "✅", "Committed"}
        :failed -> {"bg-red-600", "❌", "Failed"}
        _ -> {"bg-gray-600", "?", "Unknown"}
      end

    assigns = assign(assigns, bg_class: bg_class, icon: icon, text: text)

    ~H"""
    <span class={"text-xs px-2 py-1 rounded #{@bg_class} text-white flex items-center gap-1"}>
      <span>{@icon}</span>
      <span>{@text}</span>
    </span>
    """
  end

  # Helper functions

  defp format_time(nil), do: "-"

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp event_icon(type) do
    case type do
      :blueprint_ready -> "📐"
      :code_ready -> "✍️"
      :validation_passed -> "✅"
      :validation_failed -> "❌"
      :file_validated -> "📦"
      :execution_success -> "🚀"
      :execution_failure -> "💥"
      :agent_surrender -> "🏳️"
      :project_finished -> "🏁"
      _ -> "📌"
    end
  end

  defp event_label(type) do
    case type do
      :blueprint_ready -> "Blueprint Ready"
      :code_ready -> "Code Generated"
      :validation_passed -> "Validation Passed"
      :validation_failed -> "Validation Failed"
      :file_validated -> "File Committed"
      :execution_success -> "Execution Success"
      :execution_failure -> "Execution Failed"
      :agent_surrender -> "Agent Surrendered"
      :project_finished -> "Project Finished"
      _ -> to_string(type)
    end
  end

  defp event_description(event) do
    case event.data do
      %{filename: filename} -> filename
      %{file_count: count} -> "#{count} files"
      _ -> event.project_id
    end
  end
end
