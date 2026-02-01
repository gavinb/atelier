defmodule AtelierWeb.ErrorHTML do
  @moduledoc """
  Error HTML rendering for the dashboard.
  """

  use AtelierWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
