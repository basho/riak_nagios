-module(check_riak_repl).

-export([run/2]).

run(Options, _NonOptArgs) ->
    Node = proplists:get_value(node, Options),
    Checks = check_repl(Node),
    case lists:member(unknown, Checks) of
        true ->
            unknown();
        false ->
            case lists:member(socket_error, Checks) of
                true ->
                    socket_error();
                false ->
                    okay()
            end
    end.

check_repl(Node) ->
    case is_leader(Node) of
        true ->
            Clients = check_repl(Node, riak_repl_client_sup),
            Servers = check_repl(Node, riak_repl_server_sup),
            Clients ++ Servers;
        false ->
            []
    end.

check_repl(Node, Sup) ->
    Pids = repl_pids(Node, Sup),
    [check_repl_pid(Node, Pid) || Pid <- Pids].

repl_pids(Node, Sup) ->
    Nodes = riak_nodes(Node),
    {ResL, _} = rpc:multicall(Nodes, supervisor, which_children, [Sup]),
    Children = lists:flatten([Res || Res <- ResL, filter_badrpc(Res)]),
    [Pid || {_,Pid,_,_} <- Children, Pid /= undefined].

check_repl_pid(Node, Pid) ->
    case rpc:call(Node, erlang, process_info, [Pid]) of
        undefined ->
            unknown;
        Info ->
            Links = proplists:get_value(links, Info),
            Port = first_port(Links),
            case Port of
                undefined ->
                    %% no port to check
                    ok;
                _ ->
                    case port_info(Port) of
                        undefined ->
                            %% port is closed
                            Pid ! {tcp_closed, Port},
                            socket_error;
                        _ ->
                            case sockname(Port) of
                                {ok, _} ->
                                    ok;
                                {error, _Reason} ->
                                    %% something has gone wrong
                                    close_port(Port),
                                    Pid ! {tcp_closed, Port},
                                    socket_error
                            end
                    end
            end
    end.

first_port([Link|_Links]) when is_port(Link) -> Link;
first_port([_|Links]) -> first_port(Links);
first_port([]) -> undefined.

sockname(Socket) ->
    Node = erlang:node(Socket),
    rpc:call(Node, inet, sockname, [Socket]).

port_info(Socket) ->
    Node = erlang:node(Socket),
    rpc:call(Node, erlang, port_info, [Socket]).

close_port(Socket) ->
    Node = erlang:node(Socket),
    rpc:call(Node, erlang, port_close, [Socket]).

is_leader(Node) ->
    rpc:call(Node, riak_repl_leader, leader_node, []) == Node.

riak_nodes(Node) ->    
    rpc:call(Node, riak_core_node_watcher, nodes, [riak_kv]).

filter_badrpc({badrpc, _}) -> false;
filter_badrpc(_) -> true.

unknown() ->
    {unknown, "Unexpected return from process_info", []}.

socket_error() ->
    {ok, "Socket errors were detected on some replication connections. These errors have been logged on the Riak node. No action is required", []}.

okay() ->
    {ok, "Replication links working correctly.", []}.
