-module(mongoose_wpool_rabbit).
-behaviour(mongoose_wpool).

% mongoose_wpool callbacks
-export([init/0, start/4, stop/2, instrumentation/2]).

-spec init() -> ok | {error, any()}.
init() ->
    {ok, _} = application:ensure_all_started([amqp_client], permanent),
    ok.

-spec start(mongooseim:host_type_or_global(), mongoose_wpool:tag(),
            mongoose_wpool:pool_opts(), mongoose_wpool:conn_opts()) -> {ok, pid()} | {error, any()}.
start(HostType, Tag, WpoolOptsIn, ConnOpts) ->
    #{confirms_enabled := Confirms, max_worker_queue_len := MaxQueueLen} = ConnOpts,
    PoolName = mongoose_wpool:make_pool_name(rabbit, HostType, Tag),
    Worker = {mongoose_rabbit_worker,
              [{amqp_client_opts, mongoose_amqp:network_params(ConnOpts)},
               {host_type, HostType},
               {pool_tag, Tag},
               {confirms, Confirms},
               {max_queue_len, MaxQueueLen}]},
    WpoolOpts = [{worker, Worker} | WpoolOptsIn],
    mongoose_wpool:start_sup_pool(rabbit, PoolName, WpoolOpts).

-spec stop(mongooseim:host_type_or_global(), mongoose_wpool:tag()) -> ok.
stop(_, _) ->
    ok.

-spec instrumentation(mongooseim:host_type_or_global(), mongoose_wpool:tag()) -> [mongoose_instrument:spec()].
instrumentation(HostType, Tag) ->
    mongoose_rabbit_worker:instrumentation(HostType, Tag).
