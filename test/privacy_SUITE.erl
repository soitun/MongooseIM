%%%-------------------------------------------------------------------
%%% @author bartek
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 24. Mar 2017 13:26
%%%-------------------------------------------------------------------
-module(privacy_SUITE).
-author("bartek").
-compile([export_all, nowarn_export_all]).

-include_lib("exml/include/exml.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("mod_privacy.hrl").
-include("mongoose.hrl").
-include("jlib.hrl").

-define(ALICE, jid:from_binary(<<"alice@localhost">>)).
-define(BOB, jid:from_binary(<<"bob@localhost">>)).
-define(JEFF, jid:from_binary(<<"jeff@localhost">>)).
-define(ACC_PARAMS, #{location => ?LOCATION,
                      lserver => (?ALICE)#jid.lserver,
                      host_type => (?ALICE)#jid.lserver,
                      from_jid => ?ALICE,
                      to_jid => ?BOB}).

all() ->
      [ check_with_allowed,
        check_with_denied,
        check_with_denied_bob,
        check_with_bob_blocked,
        check_with_changing_stanza].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(jid),
    ok = mnesia:create_schema([node()]),
    ok = mnesia:start(),
    {ok, _} = application:ensure_all_started(exometer_core),
    mongoose_config:set_opts(opts()),
    async_helper:start(Config, mongoose_instrument, start_link, []).

end_per_suite(Config) ->
    async_helper:stop_all(Config),
    mongoose_config:erase_opts(),
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    application:stop(exometer_core),
    ok.

init_per_testcase(_, C) ->
    mongooseim_helper:start_link_loaded_hooks(),
    mongoose_modules:start(),
    C.

end_per_testcase(_, _) ->
    mongoose_modules:stop().

opts() ->
    #{hosts => [<<"localhost">>],
      host_types => [],
      {modules, <<"localhost">>} =>
          #{mod_privacy => config_parser_helper:default_mod_config(mod_privacy)},
      instrumentation => config_parser_helper:default_config([instrumentation])}.

check_with_allowed(_C) ->
    Acc = mongoose_acc:new(?ACC_PARAMS#{element => message()}),
    Acc1 = make_check(Acc, userlist(none), ?BOB, out, allow),
    Acc2 = make_check(Acc1, userlist(none), ?BOB, in, allow),
    Acc3 = make_check(Acc2, userlist(none), ?JEFF, out, allow),
    _Acc4 = make_check(Acc3, userlist(none), ?JEFF, in, allow),
    ok.

check_with_denied(_C) ->
    % message
    Acc = mongoose_acc:new(?ACC_PARAMS#{element => message()}),
    Acc1 = make_check(Acc, userlist(deny_all_message), ?BOB, out, allow),
    Acc2 = make_check(Acc1, userlist(deny_all_message), ?BOB, in, deny),
    Acc3 = make_check(Acc2, userlist(deny_all_message), ?JEFF, out, allow),
    _Acc4 = make_check(Acc3, userlist(deny_all_message), ?JEFF, in, deny),
    % presence
    NAcc = mongoose_acc:new(?ACC_PARAMS#{element => presence()}),
    NAcc1 = make_check(NAcc, userlist(deny_all_message), ?BOB, out, allow),
    NAcc2 = make_check(NAcc1, userlist(deny_all_message), ?BOB, in, allow),
    NAcc3 = make_check(NAcc2, userlist(deny_all_message), ?JEFF, out, allow),
    _NAcc4 = make_check(NAcc3, userlist(deny_all_message), ?JEFF, in, allow),
    ok.

check_with_denied_bob(_C) ->
    Acc = mongoose_acc:new(?ACC_PARAMS#{element => message()}),
    Acc1 = make_check(Acc, userlist(deny_all_message), ?BOB, out, allow),
    Acc2 = make_check(Acc1, userlist(deny_all_message), ?BOB, in, deny),
    Acc3 = make_check(Acc2, userlist(none), ?JEFF, out, allow),
    _Acc4 = make_check(Acc3, userlist(none), ?JEFF, in, allow),
    ok.

check_with_bob_blocked(_C) ->
    Acc = mongoose_acc:new(?ACC_PARAMS#{element => message()}),
    Acc1 = make_check(Acc, userlist(block_bob), ?BOB, out, block),
    Acc2 = make_check(Acc1, userlist(block_bob), ?BOB, in, allow),
    Acc3 = make_check(Acc2, userlist(none), ?JEFF, out, allow),
    _Acc4 = make_check(Acc3, userlist(none), ?JEFF, in, allow),
    % presence
    NAcc = mongoose_acc:new(?ACC_PARAMS#{element => presence()}),
    NAcc1 = make_check(NAcc, userlist(block_bob), ?BOB, out, block),
    NAcc2 = make_check(NAcc1, userlist(block_bob), ?BOB, in, allow),
    NAcc3 = make_check(NAcc2, userlist(block_bob), ?JEFF, out, allow),
    _NAcc4 = make_check(NAcc3, userlist(block_bob), ?JEFF, in, allow),
    ok.

check_with_changing_stanza(_C) ->
    % message
    M = message(),
    P = presence(),
    Ul = userlist(deny_all_message),
    Acc = mongoose_acc:new(?ACC_PARAMS#{element => M}),
    Acc1 = make_check({Acc, M}, Ul, ?BOB, out, allow),
    Acc2 = make_check({Acc1, M}, Ul, ?BOB, in, deny),
    Acc3 = make_check({Acc2, M}, Ul, ?JEFF, out, allow),
    Acc4 = make_check({Acc3, M}, Ul, ?JEFF, in, deny),
    % and now we have the same accumulator, but we are checking
    % different stanza (I don't think it ever happens but kzemek
    % justly pointed out that we should provide for it)
    Acc5 = make_check({Acc4, P}, Ul, ?BOB, out, allow),
    Acc6 = make_check({Acc5, P}, Ul, ?BOB, in, allow),
    Acc7 = make_check({Acc6, P}, Ul, ?JEFF, out, allow),
    _Acc8 = make_check({Acc7, P}, Ul, ?JEFF, in, allow).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%5

make_check(Acc, PList, To, Dir, Exp) ->
    Server = <<"localhost">>,
    User = <<"alice">>,
    {Res, Acc1} = mongoose_privacy:privacy_check_packet(Acc, jid:make(User, Server, <<>>),
                                                        PList, To, Dir),
    ?assertEqual(Exp, Res),
    Acc1.

userlist(deny_all_message) ->
    It = #listitem{action = deny, order = 1, match_message = true},
    #userlist{name= <<"deny_all_message">>, list = [It]};
userlist(block_bob) ->
    It = #listitem{type = jid, value = {<<"bob">>, <<"localhost">>, <<>>},
        action = block, order = 1, match_all = true},
    #userlist{name = <<"block_bob">>, list = [It]};
userlist(_) ->
    #userlist{name = <<"empty">>}.


presence() ->
     #xmlel{name = <<"presence">>,
            attrs = #{<<"xml:lang">> => <<"en">>},
            children = []}.

message() ->
    #xmlel{name = <<"message">>,
           attrs = #{<<"type">> => <<"chat">>, <<"to">> => <<"bob@localhost">>},
           children = [#xmlel{name = <<"body">>,
                              children = [#xmlcdata{content = <<"roar!">>}]}]}.
