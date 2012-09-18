-module(check_node_escript_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("eunit_helper/include/eunit_helper.hrl").

setup() ->
    net_kernel:start(['t@127.0.0.1']),
    erlang:set_cookie(node(), c),
    os:cmd("cd .. && make REBAR_CONFIG=test/rebar.config.script escript").

cleanup(_) ->
    net_kernel:stop().

should_fail_on_unknown_check() ->
    ?assertMatch("UNKNOWN: Unknown check foo" ++ _, os:cmd("./check_node --node t@127.0.0.1 --cookie c foo")).

should_fail_with_empty_cookie_file() ->
    filelib:ensure_dir("empty_cookie/.erlang.cookie"),
    file:write_file("empty_cookie/.erlang.cookie", <<"">>),
    ?assertEqual("UNKNOWN: The cookie file \"empty_cookie/.erlang.cookie\" is empty.", os:cmd("HOME=empty_cookie ./check_node foo")).

should_fail_with_bad_cookie_file_permissions() ->
    filelib:ensure_dir("bad_permissions/.erlang.cookie"),
    file:write_file("bad_permissions/.erlang.cookie", <<"cookie">>),
    os:cmd("chmod 444 bad_permissions/.erlang.cookie"),
    ?assertEqual("UNKNOWN: The cookie file \"bad_permissions/.erlang.cookie\" must only be accessible by owner", os:cmd("HOME=bad_permissions ./check_node foo")).
