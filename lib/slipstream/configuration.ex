defmodule Slipstream.Configuration do
  @definition [
    uri: [
      doc: """
      The endpoint to which the websocket will connect. Schemes of "ws" and
      "wss" are supported, and a scheme must be provided. Either binaries or
      `URI` structs are accepted. E.g. `"ws://localhost:4000/socket/websocket"`.
      """,
      type: {:custom, __MODULE__, :parse_uri, []},
      required: true
    ],
    heartbeat_interval_msec: [
      doc: """
      The time between heartbeat messages. A value of `0` will disable automatic
      heartbeat sending. Note that a Phoenix.Channel will close out a connection
      after 60 seconds of inactivity (`60_000`).
      """,
      type: :non_neg_integer,
      default: 30_000
    ],
    headers: [
      doc: """
      A set of headers to merge with the request headers when GETing the
      websocket URI. Headers must be provided as two-tuples where both elements
      are binaries. Casing of these headers is inconsequential.
      """,
      type: {:list, {:custom, __MODULE__, :parse_pair_of_strings, []}},
      default: []
    ],
    json_parser: [
      doc: """
      A JSON parser module which exports at least `encode/1` and `decode/2`.
      """,
      type: :atom,
      default: Jason
    ],
    reconnect_after_msec: [
      doc: """
      A list of times to reference for trying reconnection when
      `Slipstreamm.reconnect/0` is used to request reconnection. The msec time
      will be fetched based on its position in the list with
      `Enum.at(reconnect_after_msec, try_number)`. If the number of tries
      exceeds the length of the list, the final value will be repeated.
      """,
      type: {:list, :non_neg_integer},
      default: [10, 50, 100, 150, 200, 250, 500, 1_000, 2_000, 5_000]
    ],
    rejoin_after_msec: [
      doc: """
      A list of times to reference for trying to rejoin a topic when
      `Slipstreamm.rejoin/0` is used. The msec time
      will be fetched based on its position in the list with
      `Enum.at(rejoin_after_msec, try_number)`. If the number of tries
      exceeds the length of the list, the final value will be repeated.
      """,
      type: {:list, :non_neg_integer},
      default: [100, 500, 1_000, 2_000, 5_000, 10_000]
    ],
    gun_open_options: [
      doc: """
      A map of options to pass to `:gun.open/3`. See the `:gun` documentation
      for more information. Note that `:gun` does not support websocket over
      HTTP2 and that `:gun` naively prefers HTTP2 when connecting over TLS.
      The `:protocols => [:http]` option will be merged in by default to allow
      `"wss"` connections out of the box.
      """,
      type: {:custom, __MODULE__, :parse_gun_open_options, []},
      default: %{protocols: [:http]}
    ]
  ]

  @moduledoc """
  Configuration for a Slipstream websocket connection

  Slipstream server process configuration is passed in with
  `Slipstream.connect/2` (or `Slipstream.connect!/2`), and so all configuration
  is evauated and validated at runtime, as opposed to compile-time validation.
  You should not expect to see validation errors on configuration unless you
  force the validation at compile-time, e.g.:

      # you probably don't want to do this...
      defmodule MyClient do
        @config Application.compile_env!(:my_app, __MODULE__)

        use Slipstream

        def start_link(args) do
          Slipstream.start_link(__MODULE__, args, name: __MODULE__)
        end

        def init(_args), do: {:ok, connect!(@config)}

        ..
      end

  This approach will validate the configuration at compile-time, but you
  will be unable to change the configuration after compilation, so any
  secrets contained in the configuration (e.g. a basic-auth request header)
  will be compiled into the beam files.

  See the docs for `c:Slipstream.init/1` for a safer approach.

  ## Options

  #{NimbleOptions.docs(@definition)}

  Note that a Phoenix.Channel defined with

  ```elixir
  socket "/socket", UserSocket, ..
  ```

  Can be connected to at `/socket/websocket`.
  """

  defstruct Keyword.keys(@definition)

  @type t :: %__MODULE__{
          uri: %URI{},
          heartbeat_interval_msec: non_neg_integer(),
          headers: [{String.t(), String.t()}],
          json_parser: module(),
          reconnect_after_msec: [non_neg_integer()],
          rejoin_after_msec: [non_neg_integer()]
        }

  @known_schemes ~w[ws wss]

  @doc """
  Validates a proposed configuration
  """
  @doc since: "1.0.0"
  @spec validate(Keyword.t()) ::
          {:ok, t()} | {:error, %NimbleOptions.ValidationError{}}
  def validate(opts) do
    case NimbleOptions.validate(opts, @definition) do
      {:ok, validated} -> {:ok, struct(__MODULE__, validated)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates a proposed configuration, raising on error
  """
  @spec validate!(Keyword.t()) :: t()
  def validate!(opts) do
    validated = NimbleOptions.validate!(opts, @definition)
    struct(__MODULE__, validated)
  end

  @doc false
  def parse_uri(proposed_uri) when is_binary(proposed_uri) do
    parse_uri(URI.parse(proposed_uri))
  end

  def parse_uri(%URI{} = proposed_uri) do
    with %URI{} = uri <- proposed_uri |> assume_port(),
         {:scheme, scheme} when scheme in @known_schemes <-
           {:scheme, uri.scheme},
         {:port, port} when is_integer(port) and port > 0 <- {:port, uri.port} do
      {:ok, uri}
    else
      {:port, bad_port} ->
        {:error,
         "unparseable port value #{inspect(bad_port)}: please provide a positive-integer value"}

      {:scheme, scheme} ->
        {:error,
         "unknown scheme #{inspect(scheme)}: only #{inspect(@known_schemes)} are accepted"}
    end
  end

  def parse_uri(unparsed) do
    {:error, "could not parse #{inspect(unparsed)} as a binary or URI struct"}
  end

  defp assume_port(%URI{scheme: "ws", port: nil} = uri),
    do: %URI{uri | port: 80}

  defp assume_port(%URI{scheme: "wss", port: nil} = uri),
    do: %URI{uri | port: 443}

  defp assume_port(uri), do: uri

  @doc false
  def parse_pair_of_strings({key, value})
      when is_binary(key) and is_binary(value) do
    {:ok, {key, value}}
  end

  def parse_pair_of_strings(unparsed) do
    {:error, "could not parse #{inspect(unparsed)} as a two-tuple of strings"}
  end

  @doc false
  def parse_gun_open_options(options) when is_map(options) do
    {:ok, Map.merge(%{protocols: [:http]}, options)}
  end

  def parse_gun_open_options(unknown) do
    {:error, "gun options must be a map, got #{inspect(unknown)}"}
  end
end
