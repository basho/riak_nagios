-module(check_node_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("eunit_helper/include/eunit_helper.hrl").

-export([run/2]).

run(_, _) ->
    erlang:error(check_node_tests).

cleanup_each(_, _) ->
    net_kernel:stop().

should_fail_when_using_an_unknown_check() ->
    Options = [{check, unknown_check}] ++ default_options(),
    ?assertMatch({unknown, "Unknown check" ++ _, _}, check_node:run(Options, [], [])).

should_fail_gracefully_when_given_a_bad_cookie() ->
    Options = [{cookie, "badcookie"}] ++ default_options(),
    ?assertMatch({unknown, "~w: ~w", [badarg, _]}, check_node:run(Options, [], [])).

should_fail_gracefully_when_check_crashes() ->
    Checks = [{node_tests, check_node_tests}],
    Options = [{check, node_tests}] ++ default_options(),
    ?assertMatch({unknown, "~w: ~w", [check_node_tests, _]}, check_node:run(Options, [], Checks)).

default_options() ->
    [{name, 't@127.0.0.1'}, {node, 't@127.0.0.1'}, {cookie, c}].
