%%
%% Carrot macros for API calls
%%

-define(CARROT_PRODUCER_START(),
        carrot_producer:start(?MODULE)).

-define(CARROT_PRODUCER_SEND_MESSAGE(Payload),
        carrot_producer:send_message(?MODULE, Payload)).

-define(CARROT_PRODUCER_SEND_MESSAGE(Payload, RoutingKey),
        carrot_producer:send_message(?MODULE, Payload, RoutingKey)).

-define(CARROT_PRODUCER_SEND_MESSAGE(Payload, RoutingKey, Props),
        carrot_producer:send_message(?MODULE, Payload, RoutingKey, Props)).

-define(CARROT_PRODUCER_SYNC_SEND_MESSAGE(Payload),
        carrot_producer:sync_send_message(?MODULE, Payload)).

-define(CARROT_PRODUCER_SYNC_SEND_MESSAGE(Payload, RoutingKey),
        carrot_producer:sync_send_message(?MODULE, Payload, RoutingKey)).

-define(CARROT_PRODUCER_SYNC_SEND_MESSAGE(Payload, RoutingKey, Props),
        carrot_producer:sync_send_message(?MODULE, Payload, RoutingKey, Props)).

-define(CARROT_CONSUMER_START(),
        carrot_consumer:start(?MODULE)).

-define(CARROT_CONSUMER_START(Id),
        carrot_consumer:start(?MODULE, Id)).

-define(CARROT_RPC_SERVER_START(),
        carrot_rpc_server:start(?MODULE)).

-define(CARROT_RPC_CLIENT_START(),
        carrot_rpc_client:start(?MODULE)).

-define(CARROT_RPC_CLIENT_CALL(Payload),
        carrot_rpc_client:call_server(?MODULE, Payload)).
