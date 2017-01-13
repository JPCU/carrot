-module(gen_consumer).

-behaviour(carrot_consumer).

-compile(export_all).

-include("carrot_api.hrl").

start(Id) -> ?CARROT_CONSUMER_START(Id).

consumer_name() -> ?MODULE.

received_init_msg() ->
    gproc_ps:publish(l, ?MODULE, {connected, self()}),
    ok.

received_msg(DeliveryTag, Msg, Props) ->
    gproc_ps:publish(l, ?MODULE, {event, {Msg, self(), Props}}),
    carrot_consumer:ack_message(self(), DeliveryTag).
