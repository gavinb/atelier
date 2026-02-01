defmodule AtelierWeb.CoreComponents do
  @moduledoc """
  Provides core UI components for the Atelier dashboard.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash messages.
  """
  attr :flash, :map, required: true
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-4 right-4 z-50 w-80 p-4 rounded-lg shadow-lg",
        @kind == :info && "bg-emerald-500 text-white",
        @kind == :error && "bg-red-500 text-white"
      ]}
      {@rest}
    >
      <p class="text-sm font-medium">
        {render_slot(@inner_block) || msg}
      </p>
      <button type="button" class="absolute top-2 right-2 text-white/80 hover:text-white">
        <span class="sr-only">Close</span>
        ✕
      </button>
    </div>
    """
  end

  @doc """
  Renders a group of flash messages.
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div>
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  defp hide(js, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end
end
