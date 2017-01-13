-module(carrot).

-export([start/0,
         config/1,
         exchange_declare/4,
         queue_declare/3,
         callback_queue_declare/1,
         queue_bind/4,
         queue_sub/3,
         prefix_name_as_bin/2,
         to_p_basic/1,
         to_list/1,
         ref/2,
         ref/3
        ]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

%%

start() -> application:ensure_all_started(carrot).

-spec config(atom()) -> any().
config(rabbit_host = Key) ->
    get_env(Key, "localhost");
config(rabbit_port = Key) ->
    list_to_integer(get_env(Key, "5672"));
config(Key) ->
    {ok, Cfg} = application:get_env(Key),
    Cfg.

-spec get_env(atom(), any()) -> any().
get_env(Key, Default) ->
    case os:getenv(os_env_key(Key)) of
        false  -> application:get_env(carrot, Key, Default);
        Val -> Val
    end.

os_env_key(Key) ->
    string:to_upper(atom_to_list(Key)).

-spec prefix_name_as_bin(list(), list()) -> binary().
prefix_name_as_bin(Prefix, Name) ->
    PrefixBin = list_to_binary(Prefix),
    NameBin = list_to_binary(Name),
    <<PrefixBin/binary, ".", NameBin/binary>>.

-spec exchange_declare(pid(), binary(), binary(), boolean()) -> ok.
exchange_declare(Channel, Name, Type, IsDurable) ->
    Exchange = #'exchange.declare'{
                  exchange = Name,
                  type = Type,
                  durable = IsDurable
                 },
    #'exchange.declare_ok'{} = amqp_channel:call(Channel, Exchange),
    ok.

-spec queue_declare(pid(), binary(), boolean()) -> {ok, term()}.
queue_declare(Channel, Name, IsDurable) ->
    QueueDeclare = #'queue.declare'{
                      queue = Name,
                      durable = IsDurable
                     },
    #'queue.declare_ok'{queue = Queue} =
        amqp_channel:call(Channel, QueueDeclare),
    {ok, Queue}.

-spec callback_queue_declare(pid()) -> {ok, term()}.
callback_queue_declare(Channel) ->
    QueueDeclare = #'queue.declare'{
                      exclusive = true,
                      auto_delete = true
                     },
    #'queue.declare_ok'{queue = Queue} =
        amqp_channel:call(Channel, QueueDeclare),
    {ok, Queue}.

-spec queue_bind(pid(), term(), binary(), binary()) -> ok.
queue_bind(Channel, Queue, ExchangeName, RoutingKey) ->
    Binding = #'queue.bind'{queue       = Queue,
                            exchange    = ExchangeName,
                            routing_key = RoutingKey},
    #'queue.bind_ok'{} = amqp_channel:call(Channel, Binding),
    ok.

-spec queue_sub(pid(), term(), pid()) -> {ok, term()}.
queue_sub(Channel, Queue, Pid) ->
    QueueSub = #'basic.consume'{queue = Queue},
    #'basic.consume_ok'{consumer_tag = ConsumerTag} =
        amqp_channel:subscribe(Channel, QueueSub, Pid),
    {ok, ConsumerTag}.

-spec to_p_basic(map()) -> #'P_basic'{}.
to_p_basic(Props) -> maps:fold(fun to_p_basic/3, #'P_basic'{}, Props).

-spec to_p_basic(term(), term(), #'P_basic'{}) -> #'P_basic'{}.
to_p_basic(delivery_mode, V, A)    -> A#'P_basic'{delivery_mode = V};
to_p_basic(correlation_id, V, A)   -> A#'P_basic'{correlation_id = V};
to_p_basic(timestamp, V, A)        -> A#'P_basic'{timestamp = V};
to_p_basic(app_id, V, A)           -> A#'P_basic'{app_id = V};
to_p_basic(headers, V, A)          -> A#'P_basic'{headers = V};
to_p_basic(type, V, A)             -> A#'P_basic'{type = V};
to_p_basic(content_type, V, A)     -> A#'P_basic'{content_type = V};
to_p_basic(content_encoding, V, A) -> A#'P_basic'{content_encoding = V};
to_p_basic(reply_to, V, A)         -> A#'P_basic'{reply_to = V};
to_p_basic(_, _, A)                -> A.

-spec ref(atom(), atom()) -> atom().
ref(A, B) -> list_to_atom(atom_to_list(A) ++ "_" ++ atom_to_list(B)).

-spec ref(atom(), atom(), integer() | binary() | atom() | list()) -> atom().
ref(A, B, C) ->
    CL = to_list(C),
    list_to_atom(atom_to_list(A) ++ "_" ++ atom_to_list(B) ++ "_" ++ CL).

-spec to_list(integer() | binary() | atom() | list()) -> list().
to_list(V) when is_integer(V) -> integer_to_list(V);
to_list(V) when is_binary(V)  -> binary_to_list(V);
to_list(V) when is_atom(V)    -> atom_to_list(V);
to_list(V) when is_list(V)    -> lists:flatten(V).
