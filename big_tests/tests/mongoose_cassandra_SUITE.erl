%%' Copyright © 2012-2017 Erlang Solutions Ltd
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%.

-module(mongoose_cassandra_SUITE).
-compile([export_all, nowarn_export_all]).

%%
%%' Imports
%%

-import(distributed_helper, [mim/0,
                             require_rpc_nodes/1,
                             rpc/4]).

%%.
%%' Preprocessor directives
%%

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%%.
%%' Configuration
%%

-define(TEST_DB_POOL_NAME,          default).
-define(TEST_KEYSPACE_NAME,         "mongooseim").
-define(TEST_TABLE_NAME,            "test_table").

%% zazkia TCP proxy API endpoint configuration
%% This endpoint will be used to drop Cassandra connections while running some tests from this suite
%% zazkia TCP proxy is required to run this suite unless group 'not_so_happy_cases' is disabled
-define(TCP_PROXY_API_HOST,         "localhost").
-define(TCP_PROXY_API_PORT,         9191).
-define(TCP_PROXY_SERVICE_NAME,     "cassandra").

%%.
%%' Common Test prelude
%%

suite() ->
    require_rpc_nodes([mim]) ++ [
        {require, ejabberd_node},
        {require, ejabberd_cookie}
    ].

all() ->
    [
        {group, happy_cases},
        {group, not_so_happy_cases}
        %{group, stress_cases} % not intended for CI, uncomment for manual stress test
    ].

groups() ->
    G = [
         {happy_cases,          [parallel], happy_cases()},
         {not_so_happy_cases,   [sequence], not_so_happy_cases()},
         {stress_cases,         [sequence], stress_cases()}
        ],
    ct_helper:repeat_all_until_all_ok(G).

happy_cases() ->
    [
        test_query,
        empty_write_should_succeed,
        single_row_read_write_should_succeed,
        small_batch_read_write_should_succeed,
        big_batch_read_write_should_succeed,
        big_objects_read_write_should_succeed
    ].

not_so_happy_cases() ->
    [
     should_work_after_restart_of_cqerl_cluster,
     should_work_after_connection_reset
    ].

stress_cases() ->
    [
     big_batch_read_write_unstable_connection_should_succeed
    ].

init_per_suite(Config) ->
    application:ensure_all_started(gun),
    mongoose_helper:inject_module(?MODULE),

    case mam_helper:is_cassandra_enabled() of
        true ->
            [{pool, ?TEST_DB_POOL_NAME} | Config];
        false ->
            {skip, no_cassandra_configured}
    end.

end_per_suite(Config) ->
    Config.

init_per_group(_GroupName, Config) ->
    common_group_config(Config).

common_group_config(Config) ->
    Config.

end_per_group(_, Config) ->
    Config.

init_per_testcase(_CaseName, Config) ->
    Config.

end_per_testcase(_CaseName, Config) ->
    Config.

%% Queries

prepared_queries() ->
    [
        {insert, "INSERT INTO " ?TEST_TABLE_NAME " (f1, f2) VALUES (?, ?)"},
        {select_by_f1, "SELECT * FROM " ?TEST_TABLE_NAME " WHERE f1 = ?"},
        {select_by_f2, "SELECT * FROM " ?TEST_TABLE_NAME " WHERE f2 = ? ALLOW FILTERING"},
        {delete, "DELETE FROM " ?TEST_TABLE_NAME " WHERE f1 = ?"}
    ].

%%.
%%' Tests
%%

sanity_check(Config) ->
    ct:pal("~p sanity check config: ~p", [?MODULE, Config]),
    ok.

test_query(_Config) ->
    ?assertMatch(ok, call(test_query, [?TEST_DB_POOL_NAME])).

empty_write_should_succeed(Config) ->
    ?assertMatch(ok, cql_write(Config, insert, [])),

    ok.

single_row_read_write_should_succeed(Config) ->
    Row = #{f1 := F1, f2 := _F2} = #{f1 => int(), f2 => str()},
    Rows = [Row],

    ?assertMatch(ok, cql_write(Config, insert, Rows)),
    ?assertMatch({ok, [Row]}, cql_read(Config, select_by_f1, #{f1 => F1})),

    ok.

small_batch_read_write_should_succeed(Config) ->
    F2 = str(),
    RowCount = 10,
    Rows = lists:sort([#{f1 => int(), f2 => F2} || _ <- lists:seq(1, RowCount)]),

    ?assertMatch(ok, cql_write(Config, insert, Rows)),

    {Result, MaybeRows} = cql_read(Config, select_by_f2, #{f2 => F2}),
    ?assertMatch({ok, _}, {Result, MaybeRows}),
    ?assertMatch(RowCount, length(MaybeRows)),
    ?assertMatch(Rows, lists:sort(MaybeRows)),

    ok.

big_batch_read_write_should_succeed(Config) ->
    F2 = str(),
    RowCount = 100,
    Rows = lists:sort([#{f1 => int(), f2 => F2} || _ <- lists:seq(1, RowCount)]),

    ?assertMatch(ok, cql_write(Config, insert, Rows)),

    {Result, MaybeRows} = cql_read(Config, select_by_f2, #{f2 => F2}),
    ?assertMatch({ok, _}, {Result, MaybeRows}),
    ?assertMatch(RowCount, length(MaybeRows)),
    ?assertMatch(Rows, lists:sort(MaybeRows)),

    ok.

big_objects_read_write_should_succeed(Config) ->
    F2 = str(1024 * 5),  %% By default batch size limit is 50kB
    RowCount = 20,       %% 20 * (1024  * 5 * 2) is way over this limit
    Rows = lists:sort([#{f1 => int(), f2 => F2} || _ <- lists:seq(1, RowCount)]),

    ?assertMatch(ok, cql_write(Config, insert, Rows)),

    {Result, MaybeRows} = cql_read(Config, select_by_f2, #{f2 => F2}),
    ?assertMatch({ok, _}, {Result, MaybeRows}),
    ?assertMatch(RowCount, length(MaybeRows)),
    ?assertMatch(Rows, lists:sort(MaybeRows)),

    ok.

should_work_after_connection_reset(_Config) ->
    reset_all_cassandra_connections(),
    wait_helper:wait_until(fun() ->
                                   call(test_query, [?TEST_DB_POOL_NAME])
                           end, ok).

should_work_after_restart_of_cqerl_cluster(_Config) ->
    Pid1 = call(erlang, whereis, [cqerl_cluster]),
    call(erlang, exit, [Pid1, kill]),
    wait_helper:wait_until(fun() ->
                                   Pid2 = call(erlang, whereis, [cqerl_cluster]),
                                   Pid1 =/= Pid2 andalso Pid2 =/= undefined
                           end, true),
    wait_helper:wait_until(fun() ->
                                   call(test_query, [?TEST_DB_POOL_NAME])
                           end, ok).

big_batch_read_write_unstable_connection_should_succeed(Config) ->
    Pid = spawn_link(fun reset_all_cassandra_connections_loop/0),
    batch_main(Config, 30, timer:seconds(20)),
    Pid ! exit.

%%.
%%' Helpers
%%

%% Changing the Interval to 1 second makes some requests fail - cqerl might be improved there
reset_all_cassandra_connections_loop() ->
    reset_all_cassandra_connections_loop(timer:seconds(5)).

reset_all_cassandra_connections_loop(Interval) ->
    reset_all_cassandra_connections(),
    receive
        exit ->
            ok
    after Interval ->
        reset_all_cassandra_connections_loop(Interval)
    end.

reset_all_cassandra_connections() ->
    {ok, ProxyPid} = gun:open(?TCP_PROXY_API_HOST, ?TCP_PROXY_API_PORT),
    %% More on this proxy's API: https://github.com/emicklei/zazkia
    Ref = gun:post(ProxyPid, <<"/routes/" ?TCP_PROXY_SERVICE_NAME "/links/close">>, []),
    gun:await(ProxyPid, Ref),
    gun:close(ProxyPid).

batch_main(Config, RowCount, TimeLeft) when TimeLeft > 0 ->
    StartTime = os:system_time(millisecond),
    F2 = str(),
    Rows = lists:sort([#{f1 => int(), f2 => F2} || _ <- lists:seq(1, RowCount)]),
    ?assertMatch(ok, call_until_no_error(cql_write, Config, insert, Rows, 5)),

    {Result, MaybeRows} = call_until_no_error(cql_read, Config, select_by_f2, #{f2 => F2}, 5),
    ?assertMatch({ok, _}, {Result, MaybeRows}),
    ?assertMatch(RowCount, length(MaybeRows)),
    ?assertMatch(Rows, lists:sort(MaybeRows)),

    RowsToDelete = [maps:with([f1], Row) || Row <- Rows],
    ?assertMatch(ok, call_until_no_error(cql_write, Config, delete, RowsToDelete, 5)),

    EndTime = os:system_time(millisecond),

    batch_main(Config, RowCount, TimeLeft - (EndTime - StartTime));
batch_main(_Config, _RowCount, _TimeLeft) ->
    ok.

%% The connection is unstable, so the query can fail sometimes.
%% In this case log the error and just repeat the failing query.
call_until_no_error(F, Config, QueryName, Arg, Retries) ->
    try call(F, cql_args(Config, [QueryName, Arg])) of
        {error, Error} when Retries > 0 ->
            ct:pal("Got error ~p from ~p(~p, ~p)", [Error, F, QueryName, Arg]),
            timer:sleep(timer:seconds(1)),
            call_until_no_error(F, Config, QueryName, Arg, Retries - 1);
        Result ->
            Result
    catch
        error:{badrpc, _} = Error when Retries > 0 ->
            ct:pal("Got exception error:~p from ~p(~p, ~p)", [Error, F, QueryName, Arg]),
            timer:sleep(timer:seconds(1)),
            call_until_no_error(F, Config, QueryName, Arg, Retries - 1)
    end.

getenv_or_fail(EnvVar) ->
    case os:getenv(EnvVar) of
        false -> error("environment variable " ++ EnvVar ++ "not defined");
        Value -> Value
    end.

call(F, A) ->
    call(mongoose_cassandra, F, A).

call(M, F, A) ->
    RPCSpec = mim(),
    rpc(RPCSpec#{timeout => timer:minutes(1)}, M, F, A).

cql_args(Config, Args) ->
    [?config(pool, Config), undefined, ?MODULE | Args].

cql_write(Config, QueryName, Rows) ->
    call(cql_write, cql_args(Config, [QueryName, Rows])).

cql_read(Config, QueryName, Params) ->
    call(cql_read, cql_args(Config, [QueryName, Params])).

int() ->
    rand:uniform(999999999).

str(Bytes) ->
    erlang:list_to_binary(
        erlang:integer_to_list(
            binary:decode_unsigned(
                crypto:strong_rand_bytes(Bytes)), 16)).

str() ->
    str(16).
