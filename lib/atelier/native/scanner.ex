defmodule Atelier.Native.Scanner do
  use Rustler, otp_app: :atelier, crate: "atelier_native_scanner"

  # When the NIF is loaded, this function is overridden by the Rust code.
  def scan_code(_code, _forbidden), do: :erlang.nif_error(:nif_not_loaded)
end
