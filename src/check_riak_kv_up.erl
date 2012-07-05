-module(check_riak_kv_up).

-export([run/2]).

run(Options, _) ->
    Node = proplists:get_value(node, Options),
    check_riak_kv_up(Node).

check_riak_kv_up(Node) ->
    Services = rpc:call(Node, riak_core_node_watcher, services, []),
    case lists:member(riak_kv, Services) of
        true ->
            {ok, "riak_kv is running on ~s", [Node]};
        false ->
            {critical, "riak_kv not found in running services on ~s: ~p", [Node, Services]}
    end.        
