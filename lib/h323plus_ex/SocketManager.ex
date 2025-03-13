defmodule SocketManager do
  @moduledoc """
  A module to handle the creation and management of Unix sockets.
  """

  # Function to create a Unix socket at the specified path
  @spec create_unix_socket(String.t()) :: {:ok, :socket.socket()} | {:error, String.t()}
  def create_unix_socket(socket_path) do
    if File.exists?(socket_path) do
      IO.puts("Removing existing socket: #{socket_path}")
      File.rm(socket_path)
    end

    # Create the Unix socket
    case :socket.open(:local, :stream, :default) do
      {:ok, socket} ->
        case :socket.bind(socket, %{family: :local, path: socket_path}) do
          :ok ->
            case :socket.listen(socket, 5) do
              :ok ->
                IO.puts("Created and listening on Unix socket at #{socket_path}")
                {:ok, socket}

              {:error, reason} ->
                IO.puts("Failed to listen on Unix socket: #{inspect(reason)}")
                {:error, reason}
            end

          {:error, reason} ->
            IO.puts("Failed to bind Unix socket: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("Failed to create Unix socket: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
