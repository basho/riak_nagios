-module(check_node_up).

-export([run/2]).

run(Options, _) ->
    Node = proplists:get_value(node, Options),
    {ok, "~s is responding to pings", [Node]}.
