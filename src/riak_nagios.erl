-module(riak_nagios).
-export([check_riak_up/0, check_repl_clients/0, check_repl_servers/0,
        check_repl_server/1, check_repl_client/1, check_ports/2]).

check_riak_up() ->
    case lists:member(riak_kv, riak_core_node_watcher:services()) of
		true -> okay("Riak is up");
		_ -> critical("Riak is down")
	end.

check_repl_clients() ->
    %% TODO: check for duplicate clients to the same site
    case is_leader() of
        true ->
            Nodes = riak_core_node_watcher:nodes(riak_kv),
            {ResL, _} = rpc:multicall(Nodes, supervisor, which_children, [riak_repl_client_sup]),
            Children = lists:flatten([Res || Res <- ResL, filter_badrpc(Res)]),
            ClientPids = [Pid || {_,Pid,_,_} <- Children, Pid /= undefined],
            Checks = [check_repl_pid(riak_repl_tcp_client, Pid) || Pid <- ClientPids],
            {BadStatus, TCPErrors} = lists:foldl(fun group_check/2, {[],[]}, Checks),
            case {BadStatus, TCPErrors} of
                {[], []} ->
                    okay("Replication clients are working correctly");
                {[], TCPErrors} ->
                    Info = [io_lib:format("~s ~w - ~w", [Site, Pid, Reason]) || {Reason, Pid, Site} <- TCPErrors],
                    Info1 = string:join(Info, ", "),
                    warning("Stalled clients were detected and restarted. No action is required. Clients: " ++ Info1);
                {BadStatus, _} ->
                    BadPids = string:join([erlang:pid_to_list(P) || P <- BadStatus], ", "),
                    critical("Unexpected return from riak_repl_tcp_client:status/1 - " ++ BadPids)
            end;
        false ->
            okay(atom_to_list(node()) ++ " is not the replication leader")
    end.

check_repl_servers() ->
    case is_leader() of
        true ->
            ServerPids = [Pid || {_,Pid,_,_} <- supervisor:which_children(riak_repl_server_sup)],
            Checks = [check_repl_pid(riak_repl_tcp_server, Pid) || Pid <- ServerPids],
            {BadStatus, TCPErrors} = lists:foldl(fun group_check/2, {[],[]}, Checks),
            case {BadStatus, TCPErrors} of
                {[], []} ->
                    okay("Replication servers are working correctly");
                {[], TCPErrors} ->
                    Info = [io_lib:format("~s ~w - ~w", [Site, Pid, Reason]) || {Reason, Pid, Site} <- TCPErrors],
                    Info1 = string:join(Info, ", "),
                    warning("Stalled servers were detected and stopped. No action is required. Servers: " ++ Info1);
                {BadStatus, _} ->
                    BadPids = string:join([erlang:pid_to_list(P) || P <- BadStatus], ", "),
                    critical("Unexpected return from riak_repl_tcp_server:status/1 - " ++ BadPids)
            end;
        false ->
            okay(atom_to_list(node()) ++ " is not the replication leader")
    end.

filter_badrpc({badrpc, _}) -> false;
filter_badrpc(_) -> true.

group_check({error, {badstatus, Pid}}, {BadStatus, TCPErrors}) ->
    {[Pid|BadStatus], TCPErrors};

group_check({error, {Reason, Pid, Site}}, {BadStatus, TCPErrors}) ->
    {BadStatus, [{Reason, Pid, Site}|TCPErrors]};

group_check(_, Acc) ->
    Acc.

check_repl_pid(Mod, Pid) ->
    case Mod:status(Pid) of
        {status, Status} ->
            {site, Site} = lists:keyfind(site, 1, Status),
            case check_repl_status(Mod, Pid, Status) of
                ok -> {ok, {Pid, Site}};
                {error, Reason} -> {error, {Reason, Pid, Site}}
            end;
        _ ->
            {error, {badstatus, Pid}}
    end.

check_repl_status(riak_repl_tcp_server, Pid, _Status) ->
    check_repl_socket(riak_repl_tcp_server, Pid);

check_repl_status(riak_repl_tcp_client, Pid, Status) ->
    case lists:keyfind(connected, 1, Status) of
        {connected, _, _} ->
            check_repl_socket(riak_repl_tcp_client, Pid);
        _ ->
            ok
    end.

check_repl_socket(Mod, Pid) ->
    %% http://www.erlang.org/doc/man/sys.html#get_status-1
    Status = sys:get_status(Pid),
    {status, _Pid, {module, gen_server}, SItem} = Status,
    [_PDict, _SysState, _ParentPid, _Dbg, Misc] = SItem,
    [State] = [State || {data,[{"State", State}]} <- Misc],
    Socket = get_repl_socket_from_state(Mod, State),
    case send_keepalive(Mod, Socket) of
        ok ->
            ok;
        {error, Reason} ->
            Pid ! {tcp_error, Socket, Reason},
            {error, Reason}
    end.

%% Depends on the internal `state` record
get_repl_socket_from_state(riak_repl_tcp_client, State) ->
    %% riak_repl_tcp_client.erl
    element(5, State);

get_repl_socket_from_state(riak_repl_tcp_server, State) ->
    %% riak_repl_tcp_server.erl
    element(3, State).

send_keepalive(Mod, Socket) ->
    Node = erlang:node(Socket),
    rpc:call(Node, Mod, send, [Socket, keepalive]).

check_repl_server(ServerSite) ->
	ReplServers = [riak_repl_tcp_server:status(P) || {_,P,_,_} <- supervisor:which_children(riak_repl_server_sup), P /= undefined],
	ReplServerStates = [S || {status, S} <- ReplServers],
	States = [lists:keyfind(state, 1, S) || S <- ReplServerStates, lists:keyfind(ServerSite, 2, S) =/= false],
	case {is_leader(), length(States)} of
		{true, 0} -> critical("Repl Server '" ++ ServerSite ++ "' was not found");
		{true, 1} -> repl_state_check(States, ServerSite, "Server");
		{true, _} -> zombies(ServerSite);
		{false, _} -> okay(atom_to_list(node()) ++ " is not repl leader")
	end.

check_repl_client(ClientSite) ->
    case is_leader() of
        true ->
            %% RPC Stats is the collection of stats from all nodes in the cluster
            %% As of repl 1.2, a client can run on any node. If this is run against an earlier version of repl,
            %% RPCStats will == [], so it's no biggie
            {Stats, _BadNodes} = rpc:multicall(riak_core_node_watcher:nodes(riak_kv), riak_repl_console, client_stats_rpc, []),
            RPCStats = lists:flatten(lists:filter(fun({badrpc, _}) ->
                    false;
                (_) -> true
                end, Stats)),
            %% The first line is local processes, which works for repl 1.1 and earlier. That line can be removed for clusters
            %% running repl 1.2+
            ReplClients = 
                [riak_repl_tcp_client:status(P) || {_,P,_,_} <- supervisor:which_children(riak_repl_client_sup), P /= undefined]
                ++
                RPCStats,
            %% ReplClients is now the union of local clients and cluster-wide clients. There may be duplicates, but that's ok
            ReplClientStates = [S || {status, S} <- ReplClients],
            States = [lists:keyfind(state, 1, S) || S <- ReplClientStates, lists:keyfind(ClientSite, 2, S) =/= false],
            repl_state_check(States, ClientSite, "Client");
        false ->
            okay(atom_to_list(node()) ++ " is not repl leader")
    end.

is_leader() ->
	riak_repl_leader:leader_node() == node().

zombies(ServerSite) ->
	[exit(P, kill) || {_,P,_,_} <- supervisor:which_children(riak_repl_server_sup), P /= undefined],
    warning("Multiple Repl Servers exist for Site '" ++ ServerSite ++"', but they have been killed. No action required").

repl_state_check([{state, State}], SiteName, ReplType) ->
	case State of
		connecting 			-> critical(ReplType ++ " '" ++ SiteName ++ "' is connecting");
		disconnected 		-> critical(ReplType ++ " '" ++ SiteName ++ "' is disconnected");
		%% Possible other states
		%% merkle_exchange
        %% merkle_recv
        %% merkle_diff
        %% wait_for_fullsync
        %% merkle_send 
        %% merkle_build
        %% merkle_xfer
        %% request_partition
        %% send_keylist
        %% wait_ack
        %% wait_for_partition
        %% build_keylist
        %% wait_keylist
        %% diff_keylist
        %% wait_peerinfo
        %% send_peerinfo
        %% merkle_wait_ack
        %% connected
		_ -> okay(ReplType ++ " '" ++ SiteName ++ "' is in an acceptable state (" ++ atom_to_list(State) ++ ")")
	end;
repl_state_check([], SiteName, ReplType) ->
    unknown(io_lib:format("~s '~s' not found", [ReplType, SiteName])).

check_ports(Norm,Crit) ->
    Limit = list_to_integer(Norm),
    Critlim = list_to_integer(Crit),
    Portcnt = length(erlang:ports()),
    if 
        (Portcnt < Limit) -> okay(io_lib:format("~b of ~b ports in use", [Portcnt, Limit]));
        (Portcnt > Critlim) -> critical(io_lib:format("~b of ~b ports in use", [Portcnt, Limit])); 
        (Portcnt >= Limit) -> warning(io_lib:format("~b of ~b ports in use", [Portcnt, Limit]))
    end.

unknown(Message) -> nagios("UNKNOWN", Message, 3).
critical(Message) -> nagios("CRITICAL", Message, 2).
warning(Message) -> nagios("WARNING", Message, 1).
okay(Message) -> nagios("OKAY", Message, 0).

nagios(Header, Message, Code) ->
    {Code, Header ++ ": " ++ Message}.
