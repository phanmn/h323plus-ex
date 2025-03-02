defmodule H323PlusEx.Native do
  @moduledoc false
  # This module contains the direct NIF bindings for the H323Plus library.
  # It's not intended to be used directly - use the H323PlusEx module instead.

  @on_load :load_nifs

  def load_nifs do
    path = :filename.join(:code.priv_dir(:h323plus_ex), 'h323plus_ex_nif')
    case :erlang.load_nif(path, 0) do
      :ok -> :ok
      {:error, {:load_failed, reason}} ->
        IO.puts "Failed to load NIF: #{reason}"
        :ok
    end
  end

  # Version information functions
  def get_version, do: error()
  def get_version_info, do: error()

  # Endpoint management functions
  def create_endpoint(_name), do: error()

  # Gatekeeper functions
  def set_gatekeeper_password(_endpoint, _password), do: error()
  def use_gatekeeper(_endpoint, _address, _identifier, _interface), do: error()
  def is_registered_with_gatekeeper(_endpoint), do: error()
  def get_gatekeeper_identifier(_endpoint), do: error()

  # Call handling functions
  def register_callback(_endpoint), do: error()
  def listen_for_calls(_endpoint, _port), do: error()
  def make_call(_endpoint, _destination), do: error()
  def accept_call(_endpoint, _token), do: error()
  def reject_call(_endpoint, _token), do: error()
  def clear_call(_endpoint, _token), do: error()

  defp error, do: :erlang.nif_error(:nif_not_loaded)
end
