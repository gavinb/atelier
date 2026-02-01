defmodule AtelierWeb.Layouts do
  @moduledoc """
  Layout components for the Atelier dashboard.
  """

  use AtelierWeb, :html

  use Phoenix.VerifiedRoutes,
    endpoint: AtelierWeb.Endpoint,
    router: AtelierWeb.Router,
    statics: AtelierWeb.static_paths()

  embed_templates "layouts/*"
end
