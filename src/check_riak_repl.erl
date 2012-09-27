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
            Pids = repl_pids(Node),
            [check_repl_pid(Node, Pid) || Pid <- Pids];
        false ->
            []
    end.

repl_pids(Node) ->
    repl_server_pids(Node) ++ repl_client_pids(Node).

repl_server_pids(Node) ->
    [Pid || {Pid, _, _} <- rpc:call(Node, riak_repl_console, server_stats_rpc, [])].

repl_client_pids(Node) ->
    [Pid || {Pid, _, _} <- rpc:call(Node, riak_repl_console, client_stats_rpc, [])].

check_repl_pid(Node, Pid) ->
    case rpc:call(Node, rpc, pinfo, [Pid, links]) of
        undefined ->
            unknown;
        {links, Links} ->
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

first_port([Port|_Links]) when is_port(Port) -> Port;
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

unknown() ->
    {unknown, "Unexpected return from process_info", []}.

socket_error() ->
    {ok, "Socket errors were detected on some replication connections. These errors have been logged on the Riak node. No action is required", []}.

okay() ->
    {ok, "Replication links working correctly.", []}.
