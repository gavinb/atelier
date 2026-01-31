# Atelier

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `atelier` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:atelier, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/atelier>.

# Testing

To test locally, ensure `ollama` is running then:

```
% iex -S mix

iex(1)> Atelier.Studio.start_project("vibe-store")
iex(2)> Atelier.Studio.request_feature("vibe-store", "A simple shopping cart module with add and remove functions")
```
