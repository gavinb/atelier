defmodule Atelier.MixProject do
  use Mix.Project

  def project do
    [
      app: :atelier,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
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
      {:sprites, git: "https://github.com/superfly/sprites-ex.git"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dotenvy, "~> 0.8"},

      # Dashboard (optional)
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:bandit, "~> 1.6"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind atelier", "esbuild atelier"],
      "assets.deploy": [
        "tailwind atelier --minify",
        "esbuild atelier --minify",
        "phx.digest"
      ]
    ]
  end
end
