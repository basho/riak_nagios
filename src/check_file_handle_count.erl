-module(check_file_handle_count).

-export([run/2]).

%% pass check level options after "--"
%% check_node file_handle_count -- --warning_threshold=50
run(Options, NonOptArgs) ->
    OptSpecList = option_spec_list(),
    case getopt:parse(OptSpecList, NonOptArgs) of
        {ok, {CmdOptions, _}} ->
            run_cmd(Options, CmdOptions);
        {error, {Reason, Data}} ->
            {unknown, "~s ~p", [Reason, Data]}
    end.

run_cmd(Options, CmdOptions) ->
    Node = proplists:get_value(node, Options),
    %% os:cmd/1 does not return exit code so we fake it the best way we can
    Cmd = "O=$(awk '{print $1}' /proc/sys/fs/file-nr 2>/dev/null);echo $?;echo ${O}",
    Resp = rpc:call(Node, os, cmd, [Cmd]),
    [ExitCode0|Output] = string:tokens(Resp, "\n"),
    ExitCode = list_to_integer(ExitCode0),
    handle_output(ExitCode, Output, Options, CmdOptions).

handle_output(0, [Count0], _Options, CmdOptions) ->
    Count = list_to_integer(Count0),
    Critical = proplists:get_value(critical, CmdOptions),
    Warning = proplists:get_value(warning, CmdOptions),
    Msg = "~B file descriptors in use",
    if
        Count >= Critical -> {critical, Msg, [Count]};
        Count >= Warning -> {warning, Msg, [Count]};
        true -> {ok, Msg, [Count]}
    end;

handle_output(ExitCode, Output, _Options, _CmdOptions) ->
    {unknown, "Exit code: ~B, message: ~w", [ExitCode, Output]}.

option_spec_list() ->
    [
    %% {Name, ShortOpt, LongOpt, ArgSpec, HelpMsg}
    {warning, undefined, "warning_threshold", {integer, 5000}, "Warning threshold"},
    {critical, undefined, "critical_threshold", {integer, 10000}, "Critical threshold"}
    ].

