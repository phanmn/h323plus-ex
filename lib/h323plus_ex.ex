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
  use GenServer

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
  Start a new H323 endpoint as a GenServer.

  ## Parameters

  * `name` - The name for the endpoint
  * `options` - Additional options (optional)

  ## Options

  * `:gatekeeper_address` - Address of the gatekeeper to register with
  * `:gatekeeper_id` - ID of the gatekeeper to register with
  * `:gatekeeper_interface` - Network interface to use for gatekeeper
  * `:gatekeeper_password` - Password to use for gatekeeper authentication
  * `:listen_port` - Port to listen on for incoming calls (default: 1720)

  ## Returns

  * `{:ok, pid}` - Reference to the started process
  * `{:error, reason}` - If there was an error

  ## Examples

      iex> H323PlusEx.start_link("MyEndpoint")
      {:ok, #PID<0.123.0>}

      iex> H323PlusEx.start_link("MyEndpoint", gatekeeper_address: "10.0.0.1")
      {:ok, #PID<0.124.0>}
  """
  @spec start_link(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(name, options \\ []) do
    GenServer.start_link(__MODULE__, [name, options], options)
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
  Set the password for the gatekeeper.

  ## Parameters

  * `endpoint` - The endpoint reference
  * `password` - The password to use for gatekeeper authentication

  ## Returns

  * `:ok` - if the password was set
  * `{:error, reason}` - if there was an error

  ## Examples

      iex> {:ok, endpoint} = H323PlusEx.create_endpoint("MyEndpoint")
      iex> H323PlusEx.set_gatekeeper_password(endpoint, "secret")
      :ok
  """
  @spec set_gatekeeper_password(endpoint(), String.t()) :: :ok | {:error, String.t()}
  def set_gatekeeper_password(endpoint, password) when is_binary(password) do
    Native.set_gatekeeper_password(endpoint, to_charlist(password))
  end

  @doc """
  Register with a gatekeeper.

  ## Parameters

  * `endpoint` - The endpoint reference
  * `address` - The address of the gatekeeper (optional)
  * `identifier` - The identifier of the gatekeeper (optional)
  * `interface` - The network interface to use (optional)

  ## Returns

  * `:ok` - if the registration was successful
  * `{:error, reason}` - if there was an error

  ## Examples

      iex> {:ok, endpoint} = H323PlusEx.create_endpoint("MyEndpoint")
      iex> H323PlusEx.use_gatekeeper(endpoint, "10.0.0.1")
      :ok
  """
  @spec use_gatekeeper(endpoint(), String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def use_gatekeeper(endpoint, address \\ "", identifier \\ "", interface \\ "") do
    address_list = if is_binary(address), do: to_charlist(address), else: ''
    id_list = if is_binary(identifier), do: to_charlist(identifier), else: ''
    iface_list = if is_binary(interface), do: to_charlist(interface), else: ''

    Native.use_gatekeeper(endpoint, address_list, id_list, iface_list)
  end

  @doc """
  Check if the endpoint is registered with a gatekeeper.

  ## Parameters

  * `endpoint` - The endpoint reference

  ## Returns

  * `true` - if registered with a gatekeeper
  * `false` - if not registered with a gatekeeper

  ## Examples

      iex> {:ok, endpoint} = H323PlusEx.create_endpoint("MyEndpoint")
      iex> H323PlusEx.is_registered_with_gatekeeper(endpoint)
      false
  """
  @spec is_registered_with_gatekeeper(endpoint()) :: boolean()
  def is_registered_with_gatekeeper(endpoint) do
    Native.is_registered_with_gatekeeper(endpoint)
  end

  @doc """
  Get the identifier of the gatekeeper that the endpoint is registered with.

  ## Parameters

  * `endpoint` - The endpoint reference

  ## Returns

  * `{:ok, identifier}` - the gatekeeper identifier
  * `{:error, reason}` - if there was an error

  ## Examples

      iex> {:ok, endpoint} = H323PlusEx.create_endpoint("MyEndpoint")
      iex> H323PlusEx.get_gatekeeper_identifier(endpoint)
      {:ok, "GK1"}
  """
  @spec get_gatekeeper_identifier(endpoint()) :: {:ok, binary()} | {:error, String.t()}
  def get_gatekeeper_identifier(endpoint) do
    Native.get_gatekeeper_identifier(endpoint)
  end

  @doc """
  Start listening for incoming calls.

  ## Parameters

  * `endpoint` - The endpoint reference
  * `port` - Port number to listen on (default: 1720)

  ## Returns

  * `:ok` - if listening was started successfully
  * `{:error, reason}` - if there was an error

  ## Examples

      iex> {:ok, endpoint} = H323PlusEx.create_endpoint("MyEndpoint")
      iex> H323PlusEx.listen_for_calls(endpoint)
      :ok
  """
  @spec listen_for_calls(endpoint(), integer()) :: :ok | {:error, String.t()}
  def listen_for_calls(endpoint, port \\ 1720) do
    # First register for callbacks
    case Native.register_callback(endpoint) do
      :ok ->
        Native.listen_for_calls(endpoint, port)
      error ->
        error
    end
  end

  @doc """
  Make an outbound call to a destination.

  ## Parameters

  * `endpoint` - The endpoint reference
  * `destination` - The destination address to call

  ## Returns

  * `{:ok, call_token}` - token identifying the call
  * `{:error, reason}` - if there was an error

  ## Examples

      iex> {:ok, endpoint} = H323PlusEx.create_endpoint("MyEndpoint")
      iex> H323PlusEx.make_call(endpoint, "h323:192.168.1.101")
      {:ok, "call_token_123"}
  """
  @spec make_call(endpoint(), String.t()) :: {:ok, call_token()} | {:error, String.t()}
  def make_call(endpoint, destination) when is_binary(destination) do
    Native.make_call(endpoint, to_charlist(destination))
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
  Clear (hang up) an active call.

  ## Parameters

  * `endpoint` - The endpoint reference
  * `call_token` - The token identifying the call

  ## Returns

  * `:ok` - if the call was cleared
  * `{:error, reason}` - if there was an error

  ## Examples

      iex> H323PlusEx.clear_call(endpoint, call_token)
      :ok
  """
  @spec clear_call(endpoint(), String.t()) :: :ok | {:error, String.t()}
  def clear_call(endpoint, call_token) when is_binary(call_token) do
    Native.clear_call(endpoint, to_charlist(call_token))
  end


  @spec create_unix_socket(endpoint(), String.t()) :: {:ok, reference()} | {:error, String.t()}
  def create_unix_socket(endpoint, socket_path) when is_binary(socket_path) do
    Native.create_unix_socket(endpoint, to_charlist(socket_path))
  end

  #
  # GenServer Implementation
  #

  @impl true
  def init([name, options]) do
    case create_endpoint(name) do
      {:ok, endpoint} ->
        # Set up gatekeeper if requested
        if password = Keyword.get(options, :gatekeeper_password) do
          set_gatekeeper_password(endpoint, password)
        end

        # Start listening for calls
        listen_port = Keyword.get(options, :listen_port, 1720)
        case listen_for_calls(endpoint, listen_port) do
          :ok ->
            # Register with gatekeeper if requested
            if gk_address = Keyword.get(options, :gatekeeper_address) do
              gk_id = Keyword.get(options, :gatekeeper_id, "")
              gk_interface = Keyword.get(options, :gatekeeper_interface, "")
              use_gatekeeper(endpoint, gk_address, gk_id, gk_interface)
            end

            {:ok, %{
              endpoint: endpoint,
              calls: %{},
              options: options
            }}

          {:error, reason} ->
            {:stop, reason}
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:incoming_call, token, caller_id}, state) do
    # Handle incoming call - in a real implementation you might want to
    # forward to a user callback or implement auto-answer logic

    # For now, just log the call and store it in state
    IO.puts("Incoming call from #{caller_id}, token: #{token}")

    {:noreply, %{state | calls: Map.put(state.calls, token, %{caller_id: caller_id, state: :ringing})}}
  end

  @impl true
  def handle_info({:gatekeeper_event, success, gk_id}, state) do
    # Log gatekeeper registration events
    if success do
      IO.puts("Successfully registered with gatekeeper #{gk_id}")
    else
      IO.puts("Failed to register with gatekeeper")
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_endpoint, _from, state) do
    {:reply, {:ok, state.endpoint}, state}
  end

  @impl true
  def handle_call(:get_calls, _from, state) do
    {:reply, {:ok, state.calls}, state}
  end

  @impl true
  def handle_call({:make_call, destination}, _from, state) do
    case make_call(state.endpoint, destination) do
      {:ok, token} = result ->
        # Store the call in our state
        new_state = %{state | calls: Map.put(state.calls, token, %{
          destination: destination,
          state: :dialing
        })}
        {:reply, result, new_state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:accept_call, token}, _from, state) do
    result = accept_call(state.endpoint, token)

    # Update call state if successful
    new_state = if result == :ok do
      call_info = Map.get(state.calls, token, %{})
      %{state | calls: Map.put(state.calls, token, Map.put(call_info, :state, :active))}
    else
      state
    end

    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:reject_call, token}, _from, state) do
    result = reject_call(state.endpoint, token)

    # Remove call from state if successful
    new_state = if result == :ok do
      %{state | calls: Map.delete(state.calls, token)}
    else
      state
    end

    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:clear_call, token}, _from, state) do
    result = clear_call(state.endpoint, token)

    # Remove call from state if successful
    new_state = if result == :ok do
      %{state | calls: Map.delete(state.calls, token)}
    else
      state
    end

    {:reply, result, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up any resources
    if Map.has_key?(state, :endpoint) do
      # Clean up any active calls
      for {token, _} <- state.calls do
        clear_call(state.endpoint, token)
      end
    end

    :ok
  end
end
