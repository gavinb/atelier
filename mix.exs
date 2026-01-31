defmodule Atelier.MixProject do
  use Mix.Project

  def project do
    [
      app: :atelier,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Atelier.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rustler, "~> 0.37.1", runtime: false},
      {:phoenix_pubsub, "~> 2.2"},
      {:req, "~> 0.5.17"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
