-module(check_node).

-export([main/1]).

%% exported for testing
-export([main/2, run/3, option_spec_list/0, connect/3]).

main([]) ->
    usage();
main(Args) ->
    main(Args, checks()).

main(Args, Checks) ->
    OptSpecList = option_spec_list(),
    case getopt:parse(OptSpecList, Args) of
        {ok, {Options, NonOptArgs}} ->
            Reply = run(Options, NonOptArgs, Checks),
            handle_reply(Reply);
        {error, {Reason, Data}} ->
            handle_reply({unknown, "~s ~p", [Reason, Data]})
    end.

run(Options, NonOptArgs, Checks) ->
    try
        try_run(Options, NonOptArgs, Checks)
    catch
        _:Reason ->
            Stack = erlang:get_stacktrace(),
            {unknown, "~w: ~w", [Reason, Stack]}
    end.

try_run(Options, NonOptArgs, Checks) ->
    Name = proplists:get_value(name, Options),
    Node = proplists:get_value(node, Options),
    Cookie = proplists:get_value(cookie, Options),
    case connect(Name, Node, Cookie) of
        ok ->
            Check = proplists:get_value(check, Options),
            case run_check(Check, Options, NonOptArgs, Checks) of
                {error, unknown_check} ->
                    {unknown, "Unknown check ~s", [Check]};
                {error, Reason} ->
                    {unknown, "Error running check: ~w", [Reason]};
                Other ->
                    Other
            end;
        Other ->
            Other
    end.

connect(Name, Node, Cookie) ->
    case net_kernel:start([Name]) of
        {ok, _} ->
            erlang:set_cookie(node(), Cookie),
            case net_kernel:hidden_connect_node(Node) of
                true ->
                    ok;
                false ->
                    {critical, "Could not connect to ~s with cookie ~s", [Node, Cookie]};
                _ ->
                    {unknown, "net_kernel:connect/1 reports ~s is not alive", [Name]}
            end;
        {error, Reason} ->
            case check_cookie() of
                {error, empty_cookie, CookieFile} ->
                    {unknown, "The cookie file \"~s\" is empty.", [CookieFile]};
                {error, bad_mode, CookieFile} ->
                    {unknown, "The cookie file \"~s\" must only be accessible by owner", [CookieFile]};
                {error, Reason1, CookieFile} ->
                    {unknown, "Error accessing the cookie file \"~s\": ~w", [CookieFile, Reason1]};
                _ ->
                    {unknown, "net_kernel:start/1 error: ~w", [Reason]}
            end
    end.

run_check(Check, Options, NonOptArgs, Checks) ->
    case lists:keyfind(Check, 1, Checks) of
        {Check, Mod} ->
            Mod:run(Options, NonOptArgs);
        _ ->
            {error, unknown_check}
    end.

checks() ->
    [
        {node_up, check_node_up},
        {riak_kv_up, check_riak_kv_up},
        {file_handle_count, check_file_handle_count},
        {leveldb_compaction, check_leveldb_compaction},
        {riak_repl, check_riak_repl}
    ].

usage() ->
    getopt:usage(option_spec_list(), escript:script_name()),
    halt(1).

handle_reply({ok, Msg, Args}) ->
    okay(Msg, Args);

handle_reply({warning, Msg, Args}) ->
    warning(Msg, Args);

handle_reply({critical, Msg, Args}) ->
    critical(Msg, Args);

handle_reply({unknown, Msg, Args}) ->
    unknown(Msg, Args);

handle_reply(Reply) ->
    unknown("~w", [Reply]).

okay(Msg, Args) ->
    output(0, "OKAY: " ++ Msg, Args).

warning(Msg, Args) ->
    output(1, "WARNING: " ++ Msg, Args).

critical(Msg, Args) ->
    output(2, "CRITICAL: " ++ Msg, Args).

unknown(Msg, Args) ->
    output(3, "UNKNOWN: " ++ Msg, Args).

output(ErrorCode, Msg, Args) ->
    io:format(Msg, Args),
    halt(ErrorCode).

option_spec_list() ->
    Checks = string:join([atom_to_list(Check) || {Check, _} <- checks()], ", "),
    CheckMsg = "Check to run: " ++ Checks,
    [
     %% {Name,     ShortOpt,  LongOpt,       ArgSpec,                          HelpMsg}
     {name,        undefined, "name",        {atom, 'check_node@127.0.0.1'},   "Name of checking node"},
     {node,        undefined, "node",        {atom, 'riak@127.0.0.1'},         "Node to check"},
     {cookie,      undefined, "cookie",      {atom, riak},                     "Node cookie"},
     {check,       undefined, undefined,     atom,                             CheckMsg} 
    ].

-include_lib("kernel/include/file.hrl").

check_cookie() ->
    Home = os:getenv("HOME"),
    CookieFile = filename:join(Home, ".erlang.cookie"),
    case file:read_file(CookieFile) of
        {ok, <<"">>} ->
            {error, empty_cookie, CookieFile};
        {ok, _} ->
            case file:read_file_info(CookieFile) of
                {ok, Info} ->
                    case (Info#file_info.mode band 8#077) =:= 0 of
                        true ->
                            ok;
                        _ ->
                            {error, bad_mode, CookieFile}
                    end;
                {error, Reason} ->
                    {error, Reason, CookieFile}
            end;
        {error, Reason} ->
            {error, Reason, CookieFile}
    end.
