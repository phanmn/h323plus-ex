defmodule H323PlusEx do
  @moduledoc """
  Elixir interface for the H323Plus library.

  This module provides a high-level, Elixir-friendly API for working with H.323
  protocol for VoIP and video conferencing.

  ## Overview

  H.323 is an ITU protocol standard for audio and video communication across IP networks.
  This library provides Elixir bindings to the H323Plus implementation of the H.323 standard.

  ## Key Features

  - Create H.323 endpoints
  - Register with H.323 gatekeepers
  - Make outbound calls
  - Receive inbound calls
  - Manage call state
  """

  alias H323PlusEx.Native

  @typedoc """
  An H323 endpoint reference.
  """
  @opaque endpoint :: reference()

  @typedoc """
  A token representing an active call.
  """
  @opaque call_token :: binary()

  @doc """
  Get the version of the Opal/H323Plus library.

  ## Returns

  * `{:ok, version}` - where `version` is a binary string
  * `{:error, reason}` - if there was an error

  ## Examples

      iex> H323PlusEx.version()
      {:ok, "3.16.0"}
  """
  @spec version() :: {:ok, binary()} | {:error, String.t()}
  def version do
    Native.get_version()
  end

  @doc """
  Get detailed version information of the Opal/H323Plus library.

  ## Returns

  * `{:ok, {major, minor, build}}` - tuple containing version components
  * `{:error, reason}` - if there was an error

  ## Examples

      iex> H323PlusEx.version_info()
      {:ok, {3, 16, 0}}
  """
  @spec version_info() :: {:ok, {non_neg_integer(), non_neg_integer(), non_neg_integer()}} | {:error, String.t()}
  def version_info do
    Native.get_version_info()
  end

  @doc """
  Create an H323 endpoint.

  ## Parameters

  * `name` - The name for the endpoint

  ## Returns

  * `{:ok, endpoint}` - reference to the created endpoint
  * `{:error, reason}` - if there was an error

  ## Examples

      iex> H323PlusEx.create_endpoint("MyH323Endpoint")
      {:ok, #Reference<0.123.456.789>}
  """
  @spec create_endpoint(String.t()) :: {:ok, endpoint()} | {:error, String.t()}
  def create_endpoint(name) when is_binary(name) do
    Native.create_endpoint(to_charlist(name))
  end

  @doc """
  Start listening for incoming calls.

  ## Parameters

  * `endpoint` - The endpoint reference
  * `port` - Port number to listen on (default: 1720)
  * `options` - Additional options (not used yet)

  ## Returns

  * `:ok` - if listening was started successfully
  * `{:error, reason}` - if there was an error

  ## Examples

      iex> {:ok, endpoint} = H323PlusEx.create_endpoint("MyH323Endpoint")
      iex> H323PlusEx.listen_for_calls(endpoint)
      :ok
  """
  @spec listen_for_calls(endpoint(), integer(), keyword()) :: :ok | {:error, String.t()}
  def listen_for_calls(endpoint, port \\ 1720, _options \\ []) do
    # Register for callbacks before listening
    case Native.register_callback(endpoint) do
      :ok ->
        Native.listen_for_calls(endpoint, port)
      error ->
        error
    end
  end

  @doc """
  Accept an incoming call.

  ## Parameters

  * `endpoint` - The endpoint reference
  * `call_token` - The token identifying the call

  ## Returns

  * `:ok` - if the call was accepted
  * `{:error, reason}` - if there was an error

  ## Examples

      # In your GenServer or process handling incoming calls:
      def handle_info({:incoming_call, token, caller_id}, state) do
        H323PlusEx.accept_call(state.endpoint, token)
        # Update state with new call information
        {:noreply, state}
      end
  """
  @spec accept_call(endpoint(), String.t()) :: :ok | {:error, String.t()}
  def accept_call(endpoint, call_token) when is_binary(call_token) do
    Native.accept_call(endpoint, to_charlist(call_token))
  end

  @doc """
  Reject an incoming call.

  ## Parameters

  * `endpoint` - The endpoint reference
  * `call_token` - The token identifying the call

  ## Returns

  * `:ok` - if the call was rejected
  * `{:error, reason}` - if there was an error

  ## Examples

      # In your GenServer or process handling incoming calls:
      def handle_info({:incoming_call, token, _caller_id}, state) do
        H323PlusEx.reject_call(state.endpoint, token)
        {:noreply, state}
      end
  """
  @spec reject_call(endpoint(), String.t()) :: :ok | {:error, String.t()}
  def reject_call(endpoint, call_token) when is_binary(call_token) do
    Native.reject_call(endpoint, to_charlist(call_token))
  end

  @doc """
  Wait for an incoming call and handle it with the provided function.
  This is a convenience wrapper that creates an endpoint, starts listening,
  and handles the first incoming call.

  ## Parameters

  * `name` - The name for the endpoint
  * `callback` - Function that receives the call token and caller ID
  * `options` - Additional options

  ## Options

  * `:port` - Port to listen on (default: 1720)
  * `:timeout` - How long to wait for a call in milliseconds (default: :infinity)

  ## Returns

  * `:ok` - if the call was handled
  * `{:error, reason}` - if there was an error
  * `{:timeout}` - if no call was received within the timeout

  ## Examples

      H323PlusEx.receive_call("MyEndpoint", fn token, caller_id ->
        IO.puts("Incoming call from \#{caller_id}")
        :accept # Return :accept to accept the call, :reject to reject it
      end)
  """
  @spec receive_call(String.t(), (String.t(), String.t() -> :accept | :reject), keyword()) :: :ok | {:error, String.t()} | {:timeout}
  def receive_call(name, callback, options \\ []) when is_binary(name) and is_function(callback, 2) do
    port = Keyword.get(options, :port, 1720)
    timeout = Keyword.get(options, :timeout, :infinity)

    with {:ok, endpoint} <- create_endpoint(name),
         :ok <- listen_for_calls(endpoint, port) do
      # Wait for incoming call
      receive do
        {:incoming_call, token, caller_id} ->
          case callback.(token, caller_id) do
            :accept -> accept_call(endpoint, token)
            :reject -> reject_call(endpoint, token)
            other -> {:error, "Invalid callback return value: #{inspect(other)}"}
          end
      after
        timeout -> {:timeout}
      end
    end
  end
end
