-module(check_msg_q).

-export([run/2]).

run(Options, NonOptArgs) ->
    OptSpecList = option_spec_list(),
    case getopt:parse(OptSpecList, NonOptArgs) of
        {ok, {CmdOptions, _}} ->
            run_cmd(Options, CmdOptions);
        {error, {Reason, Data}} ->
            {unknown, "~s ~p", [Reason, Data]}
    end.

option_spec_list() ->
    [
     %% {Name, ShortOpt, LongOpt, ArgSpec, HelpMsg}
     {warning, undefined, "warning_threshold", {integer, 200}, "Warning threshold"},
     {critical, undefined, "critical_threshold", {integer, 10000}, "Critical threshold"}
    ].

run_cmd(Options, CmdOptions) ->
    Node = proplists:get_value(node, Options),
    Pids = rpc:call(Node, erlang, processes, []),
    case is_list(Pids) of
        true ->
            QTups = [{Pid0, rpc:call(Node, erlang, 
                                     process_info, 
                                     [Pid0, message_queue_len])} ||
                        Pid0 <- Pids],
            MsgCounts = [{Pid, QLen} || {Pid, {message_queue_len, QLen}} 
                                            <- QTups], 
            Highest = lists:foldl(fun({_Pid, X},Y) -> 
                                          case X > Y of 
                                              true  -> X; 
                                              false -> Y 
                                          end 
                                  end, 0, MsgCounts),

            handle_output(0, Highest, CmdOptions);
        false -> 
            {error, "process gathering failed"}
    end.

handle_output(0, Count, CmdOptions) ->
    Critical = proplists:get_value(critical, CmdOptions),
    Warning = proplists:get_value(warning, CmdOptions),
    Msg = "~B is the longest message queue.",
    if
        Count >= Critical -> {critical, Msg, [Count]};
        Count >= Warning -> {warning, Msg, [Count]};
        true -> {ok, Msg, [Count]}
    end.

