-module(check_node).

-export([main/1]).

main([]) ->
    usage();
main(Args) ->
    OptSpecList = option_spec_list(),
    case getopt:parse(OptSpecList, Args) of
        {ok, {Options, NonOptArgs}} ->
            run(Options, NonOptArgs);
        {error, {Reason, Data}} ->
            unknown("~s ~p", [Reason, Data])
    end.

run(Options, NonOptArgs) ->
    Name = proplists:get_value(name, Options),
    Node = proplists:get_value(node, Options),
    Cookie = proplists:get_value(cookie, Options),
    case connect(Name, Node, Cookie) of
        ok ->
            Check = proplists:get_value(check, Options),
            case run_check(Check, Options, NonOptArgs) of
                {ok, Msg, Args} ->
                    okay(Msg, Args);
                {warning, Msg, Args} ->
                    warning(Msg, Args);
                {critical, Msg, Args} ->
                    critical(Msg, Args);
                {unknown, Msg, Args} ->
                    unknown(Msg, Args);
                {error, unknown_check} ->
                    unknown("Unkown check ~s", [Check]);
                {error, Reason} ->
                    unknown("Could not run check: ~s", [Reason])
            end;
        {error, false} ->
            critical("Could not connect to ~s with cookie ~s", [Node, Cookie]);
        {error, ignored} ->
            unknown("net_kernel:connect/1 reports ~s is not alive", [Name]);
        {error, Reason} ->
            unknown("net_kernel:start/1 failed: ~s", [Reason])
    end.

connect(Name, Node, Cookie) ->
    case net_kernel:start([Name]) of
        {ok, _} ->
            erlang:set_cookie(node(), Cookie),
            case net_kernel:hidden_connect_node(Node) of
                true ->
                    ok;
                Other ->
                    {error, Other}
            end;
        Error ->
            Error
    end.

run_check(Check, Options, NonOptArgs) ->
    case lists:keyfind(Check, 1, checks()) of
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
        {riak_repl, check_riak_repl}
    ].

usage() ->
    getopt:usage(option_spec_list(), escript:script_name()),
    halt(1).

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
