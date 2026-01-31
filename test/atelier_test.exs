defmodule AtelierTest do
  use ExUnit.Case
  doctest Atelier

  test "greets the world" do
    assert Atelier.hello() == :world
  end
end
