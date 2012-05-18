-module(riak_nagios).
-export([check_riak_up/0, check_repl_server/1, check_repl_client/1]).


check_riak_up() ->
    case lists:member(riak_kv, riak_core_node_watcher:services()) of
		true -> okay("Riak is up");
		_ -> critical("Riak is down")
	end.

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
            ReplClients = [riak_repl_tcp_client:status(P) || {_,P,_,_} <- supervisor:which_children(riak_repl_client_sup), P /= undefined],
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


unknown(Message) -> nagios("UNKNOWN", Message, 3).
critical(Message) -> nagios("CRITICAL", Message, 2).
warning(Message) -> nagios("WARNING", Message, 1).
okay(Message) -> nagios("OKAY", Message, 0).

nagios(Header, Message, Code) ->
    {Code, Header ++ ": " ++ Message}.
