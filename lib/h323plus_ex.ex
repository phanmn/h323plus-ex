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
  Create 2 sockets for endpoint, 1 for audio and 1 for video.

  ## Parameters

  * `endpoint` - The reference of the endpoint

  ## Returns

  * `{:ok, socket(), socket()}` - 2 sockets for audio and video
  * `{:error, reason}` - if there was an error

  ## Examples

      iex> H323PlusEx.create_socket(endpoint)
      {:ok, {:"$socket", #Reference<0.424244461.3195404295.169911>},
       {:"$socket", #Reference<0.424244461.3195404295.169921>}}
  """
  @spec create_socket(endpoint()) :: {:ok, :socket.socket(), :socket.socket()} | {:error, String.t()}
  def create_socket(endpoint_ref) do
    # Define paths for audio and video sockets
    audio_socket_path = "/tmp/h323_socket/audio"
    video_socket_path = "/tmp/h323_socket/video"

    ## Create the audio and video sockets using the SocketManager
    case {SocketManager.create_unix_socket(audio_socket_path), SocketManager.create_unix_socket(video_socket_path)} do
      {{:ok, audio_sock}, {:ok, video_sock}} ->
        Agent.update(__MODULE__, fn state ->
          Map.put(state, endpoint_ref, %{audio: audio_socket_path, video: video_socket_path})
        end)
        {:ok, audio_sock, video_sock}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Send data to audio and video socket in turn each 3 seconds.

  ## Parameters

  * `endpoint` - The reference of the endpoint
  * `type` - Choose audio or video to send first
  * `data` - The data semd to the sockets

  ## Examples

      iex> H323PlusEx.loop_send_data(endpoint1, :audio, "Test data\n")
      Opened socket and connected to /tmp/h323_socket/audio
      [audio] Client connected! Waiting for messages...
      [audio] Listening for incoming data...
      [audio] Received data: "Test data\n"
      ✅ Sent audio data: "Test data\n"
      [audio] Listening for incoming data...
      Opened socket and connected to /tmp/h323_socket/video
      [video] Client connected! Waiting for messages...
      ✅ Sent video data: "Test data\n"
      [video] Listening for incoming data...
      [video] Received data: "Test data\n"
      [video] Listening for incoming data...
  """
  @spec loop_send_data(endpoint(), atom(), String.t()) :: :ok | {:error, String.t()}
  def loop_send_data(endpoint_ref, type, data) do
    case type do
      :audio ->
        send_data(endpoint_ref, :audio, data)
        Process.sleep(3000)
        loop_send_data(endpoint_ref, :video, data)
      :video ->
        send_data(endpoint_ref, :video, data)
        Process.sleep(3000)
        loop_send_data(endpoint_ref, :audio, data)
    end
  end

  ## Send data to the appropriate endpoint (audio or video)
  def send_data(endpoint_ref, type, data) do
    case Agent.get(__MODULE__, fn state -> Map.get(state, endpoint_ref) end) do
      nil ->
        IO.puts("Endpoint not found!")
        {:error, :endpoint_not_found}

      sockets ->
        socket_path =
          case type do
            :audio -> sockets.audio
            :video -> sockets.video
            _ -> raise "Unknown type: #{type}"
          end

        case Agent.get(__MODULE__, fn state -> Map.get(state, {:socket, type}) end) do
          nil ->
            case :socket.open(:local, :stream, :default) do
              {:ok, socket} ->
                case :socket.connect(socket, %{family: :local, path: socket_path}) do
                  :ok ->
                    IO.puts("Opened socket and connected to #{socket_path}")
                    # Update the socket in the agent state, so we don't have to reconnect each time we send data
                    Agent.update(__MODULE__, fn state -> Map.put(state, {:socket, type}, socket) end)
                    send_through_socket(socket, type, data)
                  {:error, reason} ->
                    IO.puts("Failed to connect to #{socket_path}: #{reason}")
                    {:error, reason}
                end
              {:error, reason} ->
                IO.puts("Failed to open socket: #{reason}")
                {:error, reason}
            end
          socket ->
            IO.puts("Already have socket, send #{data} to #{socket_path}")
            send_through_socket(socket, type, data)
        end
    end
  end

  ## Send data through the socket
  defp send_through_socket(socket, type, data) do
    case :socket.send(socket, data) do
      :ok ->
        IO.puts("✅ Sent #{type} data: #{inspect(data)}")
        {:ok}
      {:error, reason} ->
        IO.puts("Failed to send data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Start 2 processes to receive data from audio and video socket.

  ## Parameters

  * `audio_socket` - The socket for audio
  * `video_socket` - The socket for video

  ## Examples

      iex> H323PlusEx.start_receive_from_socket(audio_socket, video_socket)

  """
  @spec start_receive_from_socket(:socket.socket(), :socket.socket()) :: :ok
  def start_receive_from_socket(audio_socket, video_socket) do
    spawn(fn -> accept_and_receive(audio_socket, :audio) end)
    spawn(fn -> accept_and_receive(video_socket, :video) end)
  end

  ## Accept connection from socket and call receive data function
  defp accept_and_receive(socket, type) do
    case :socket.accept(socket) do
      {:ok, client} ->
        IO.puts("[#{type}] Client connected! Waiting for messages...")
        receive_loop(client, type)
      {:error, reason} ->
        IO.puts("[#{type}] Failed to accept connection: #{reason}")
    end
  end

  ## Receive data from the socket
  defp receive_loop(client, type) do
    IO.puts("[#{type}] Listening for incoming data...")
    case :socket.recvmsg(client, 4096, 5000) do
      {:ok, %{iov: [data]}} ->
        IO.puts("[#{type}] Received data: #{inspect(data)}")
        receive_loop(client, type)
      {:closed, data} ->
        IO.puts("[#{type}] Connection closed. Last data received: #{inspect(data)}")
        :ok
      {:error, reason} ->
        IO.puts("[#{type}] Error receiving data: #{inspect(reason)}")
        :error
    end
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

  #
  # GenServer Implementation
  #

 def create_unix_socket() do
    IO.puts("[Elixir] start create_unix_socket")
    unix_socket_path = "/tmp/h323_audio"
    if File.exists?(unix_socket_path) do
      File.rm!(unix_socket_path)
    end
    case :socket.open(:local, :stream, :default) do
      {:ok, socket} ->
        case :socket.bind(socket, %{family: :local, path: unix_socket_path}) do
          :ok ->
            case :socket.listen(socket, 5) do
              :ok ->
                IO.puts("[Elixir] UNIX socket server started at #{unix_socket_path}")
                spawn (fn -> accept_connections(socket) end)
                {:ok, socket}
              {:error, reason} ->
                IO.puts("Failed to listen on socket: #{reason}")
                {:error, reason}
            end
          {:error, reason} ->
            IO.puts("Failed to bind socket: #{reason}")
            {:error, reason}
        end
      {:error, reason} ->
        IO.puts("Failed to open socket: #{reason}")
        {:error, reason}
    end
  end

  defp accept_connections(socket) do
    {:ok, client} = :socket.accept(socket)
    IO.puts("Accepted connection from Polycommmmmmmmm")
    # send_wav(client)
    # Process.sleep(2000)
    # spawn(fn -> WavToRtp.stream_wav_to_rtp(client, "/tmp/example1.wav") end)
    handle_client(client)
    accept_connections(socket) # Keep listening for new connections
  end

  defp handle_client(client) do
    spawn(fn -> loop(client) end)
  end

  defp loop(client) do
    case :socket.recv(client, 1024) do
      {:ok, data} when byte_size(data) > 0 ->
        # IO.puts("Received data from H323: #{inspect(data)}")
        loop(client)
      _ ->
        IO.puts("Client disconnected")
        :socket.close(client)
    end
  end

  defp send_wav1(socket) do
    case File.read("/tmp/example1.alaw") do
      {:ok, data} ->
        :socket.send(socket, data)
        IO.puts("G.711 A-law audio sent successfully!")
        Process.sleep(2000)
        send_wav1(socket)

      {:error, reason} ->
        IO.puts("Failed to read audio file: #{inspect(reason)}")
    end
  end

 defp send_wav(socket) do
    File.open("/tmp/example1.wav", [:read, :binary], fn file ->
      IO.binread(file, 44)  # Skip WAV header
      stream_pcm(file, socket)
    end)
    Process.sleep(1000)
    send_wav(socket)
  end

  defp stream_pcm(file, socket) do
    case IO.binread(file, 1024) do
      :eof -> :ok
      chunk ->
        :socket.send(socket, chunk)
        Process.sleep(20)  # Adjust for real-time playback
        stream_pcm(file, socket)
    end
  end


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
        create_unix_socket()
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
  def handle_call({:update, func}, _from, state) when is_function(func, 1) do
    new_state = func.(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get, fun}, _from, state) do
    result = fun.(state)
    {:reply, result, state}
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
    # unix_socket_path = "/tmp/h323_audio"
    result = accept_call(state.endpoint, token)

    # accept_connections(unix_socket_path)
    # spawn(fn -> connect_socket() end)

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
defmodule WavToRtp do
  @rtp_payload_type 8  # G.711 A-law
  @frame_size 160  # 20ms frame (8kHz * 0.02s)

  # Read and extract PCM data from a WAV file
  def read_pcm(filename) do
    case File.read(filename) do
      {:ok, binary} ->
        << "RIFF", _::binary-size(4), "WAVE", "fmt ", _::binary-size(4),
           1::little-16, 1::little-16, 8000::little-32, _::binary-size(6), 16::little-16,
           "data", _::binary-size(4), pcm_data::binary >> = binary
        {:ok, pcm_data}

      {:error, reason} -> {:error, reason}
    end
  end

  # Convert PCM (16-bit) to G.711 A-law
  def convert_to_g711a(pcm_data) do
    pcm_data
    |> :binary.bin_to_list()
    |> Enum.chunk_every(2)
    |> Enum.map(fn [lo, hi] ->
      sample = Bitwise.bor(Bitwise.bsl(hi, 8), lo)
      sample = if sample >= 32768, do: sample - 65536, else: sample  # Correct signed conversion
      encode_alaw(sample)
    end)
    |> :binary.list_to_bin()
  end

  # Encode a single PCM sample to G.711 A-law
  defp encode_alaw(pcm) do
    a = :math.log10(abs(pcm) + 1) * 16
    seg = trunc(a)
    quant = trunc((a - seg) * 16)
    encoded = Bitwise.bor(Bitwise.bsl(seg, 4), quant)

    if pcm < 0, do: Bitwise.bxor(encoded, 0xD5), else: Bitwise.bxor(encoded, 0x55)
  end

  # Create an RTP packet
  defp create_rtp_packet(seq, timestamp, payload, ssrc \\ 12345) do
    version = 2
    padding = 0
    extension = 0
    csrc_count = 0
    marker = 0
    payload_type = @rtp_payload_type

    header = <<
      version::size(2), padding::size(1), extension::size(1), csrc_count::size(4),
      marker::size(1), payload_type::size(7), seq::big-16, timestamp::big-32, ssrc::big-32
    >>

    header <> payload
  end

  # Send RTP packets via a UNIX socket
  def send_rtp(socket, g711a_data) do
    Enum.chunk_every(:binary.bin_to_list(g711a_data), @frame_size)
    |> Enum.with_index()
    |> Enum.each(fn {payload, i} ->
      seq_num = rem(i, 65536)  # Keep sequence number within range
      timestamp = i * @frame_size  # Timestamp increments by frame size
      packet = create_rtp_packet(seq_num, timestamp, :binary.list_to_bin(payload))
      :socket.send(socket, packet)
    end)
  end

  # Main function: Read WAV, convert, and send over RTP
  def stream_wav_to_rtp(socket, wav_file) do
    case read_pcm(wav_file) do
      {:ok, pcm_data} ->
        g711a_data = convert_to_g711a(pcm_data)
        send_rtp(socket, g711a_data)
        :ok

      {:error, reason} -> {:error, reason}
    end
  end
end
