defmodule Mix.Tasks.Export do
  @moduledoc """
  Export the source code as a zip file, excluding build artifacts and dependencies.

  ## Usage

      mix export [filename]

  If no filename is provided, defaults to `atelier-source.zip`.

  ## Exclusions

  The following directories and files are excluded from the archive:
  - .git
  - .elixir_ls
  - .jj
  - _build
  - deps
  - target
  - priv
  - node_modules
  - __pycache__
  - *.pyc
  """

  use Mix.Task

  @shortdoc "Export source code as a zip file"

  @impl Mix.Task
  def run(args) do
    filename = List.first(args) || "atelier-source.zip"

    exclusions = [
      "*.git*",
      "*node_modules*",
      "*__pycache__*",
      "*.pyc",
      "*.elixir_ls*",
      "*.jj*",
      "*_build*",
      "*deps*",
      "*target*",
      "*priv*"
    ]

    exclude_args = Enum.flat_map(exclusions, fn pattern -> ["-x", pattern] end)

    # Remove existing zip if it exists
    if File.exists?(filename) do
      File.rm!(filename)
      Mix.shell().info("Removed existing #{filename}")
    end

    # Create the zip archive
    args = ["zip", "-r", filename, "."] ++ exclude_args

    Mix.shell().info("Creating #{filename}...")

    case System.cmd("zip", args -- ["zip"], env: nil, stderr_to_stdout: true) do
      {_output, 0} ->
        Mix.shell().info("Successfully created #{filename}")

      {output, code} ->
        Mix.shell().error("Failed to create archive (exit code: #{code})")
        Mix.shell().error(output)
    end
  end
end
