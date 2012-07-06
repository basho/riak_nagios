-module(check_leveldb_compaction).

-export([run/2]).

run(Options, _NonOptArgs) ->
    Node = proplists:get_value(node, Options),
    KV = rpc:call(Node, application, get_all_env, [riak_kv]),
    Level = rpc:call(Node, application, get_all_env, [eleveldb]),
    Env = [{riak_kv, KV}, {eleveldb, Level}],
    DataRoots = data_roots(Env),
    case generate_command(DataRoots) of
        {error, _} ->
            {unknown, "No LevelDB paths found", []};
        Cmd ->
            run_cmd(Node, Cmd)
    end.

run_cmd(Node, Cmd) ->
    Resp = rpc:call(Node, os, cmd, [wrap_command(Cmd)]),
    parse_resp(Resp).

parse_resp(Resp) ->
    Lines = string:tokens(Resp, "\n"),
    ExitCode = list_to_integer(lists:nth(1, Lines)),
    Output = lists:nthtail(1, Lines),
    handle_output(ExitCode, Output).

handle_output(0, Output) ->
    case length(Output) > 0 of
        true ->
            Errors = string:join(Output, ", "),
            {critical, "LevelDB compaction errors found: ~s", [Errors]};
        false ->
            {ok, "LevelDB is ok", []}
    end;

handle_output(Err, Output) ->
    FirstLine = lists:nth(1, Output),
    {unknown, "Error code: ~B, message: ~s", [Err, FirstLine]}.

data_roots(Env) ->
    data_roots([storage_backend(Env)], Env, []).

data_roots([riak_kv_eleveldb_backend|BEs], Env, Acc) ->
    DataRoot = eleveldb_global_data_root(Env),
    data_roots(BEs, Env, [DataRoot|Acc]);

data_roots([riak_cs_kv_multi_backend|BEs], Env, Acc) ->
    MoreBEs = [{BE, Options} || {_, BE, Options} <- multi_backends(Env)],
    data_roots(BEs ++ MoreBEs, Env, Acc);

data_roots([riak_kv_multi_backend|BEs], Env, Acc) ->
    MoreBEs = [{BE, Options} || {_, BE, Options} <- multi_backends(Env)],
    data_roots(BEs ++ MoreBEs, Env, Acc);

data_roots([{riak_kv_eleveldb_backend, Options}|BEs], Env, Acc) ->
    DataRoot = eleveldb_data_root(Options, Env),
    data_roots(BEs, Env, [DataRoot|Acc]);

data_roots([_|BEs], Env, Acc) ->
    data_roots(BEs, Env, Acc);

data_roots([], _, Acc) ->
    Acc.

eleveldb_data_root(Options, Env) ->
    case proplists:get_value(data_root, Options) of
        undefined ->
            eleveldb_global_data_root(Env);
        V ->
            V
    end.

eleveldb_global_data_root(Env) ->
    Env1 = proplists:get_value(eleveldb, Env),
    proplists:get_value(data_root, Env1).

multi_backends(Env) ->
    Env1 = proplists:get_value(riak_kv, Env),
    proplists:get_value(multi_backend, Env1).

storage_backend(Env) ->
    case proplists:get_value(riak_kv, Env) of
        undefined ->
            undefined;
        Env1 ->
            proplists:get_value(storage_backend, Env1)
    end.

generate_command([]) ->
    {error, no_paths};

generate_command(DataRoots) ->
    %% quote each root in case there are spaces in the path
    DataRoots1 = [io_lib:format("\"~s\"", [Root]) || Root <- DataRoots],
    Paths = string:join(DataRoots1, " "),
    io_lib:format("find ~s -name \"LOG\" -exec grep -l 'Compaction error' {} \\;", [Paths]).

wrap_command(Cmd) ->
    %% os:cmd/1 does not return the exit code so we fake it the best way we can
    "O=$(" ++ Cmd ++ " 2>&1);echo $?;echo \"$O\"".    


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

generate_command_test() ->
    Cmd = generate_command(["/data", "/data/with space"]),
    Expected = "find \"/data\" \"/data/with space\" -name \"LOG\" -exec grep -l 'Compaction error' {} \\;",
    ?assertEqual(iolist_to_binary(Expected), iolist_to_binary(Cmd)).

critical_parse_resp_test() ->
    os:cmd("mkdir critical && echo \"Compaction error\" > critical/LOG"),
    Cmd = wrap_command(generate_command(["critical"])),
    Resp = os:cmd(Cmd),
    ?assertMatch({critical, _, [_]}, parse_resp(Resp)).

ok_parse_resp_test() ->
    os:cmd("mkdir okay"),
    Cmd = wrap_command(generate_command(["okay"])),
    Resp = os:cmd(Cmd),
    ?assertMatch({ok, _, _}, parse_resp(Resp)).

unknown_parse_resp_test() ->
    Cmd = wrap_command(generate_command(["does not exist"])),
    Resp = os:cmd(Cmd),
    ?assertMatch({unknown, _, _}, parse_resp(Resp)).

bitcask_data_roots_test() ->
    Env = [{riak_kv, [{storage_backend, riak_kv_bitcask_backend}]}],
    ?assertEqual([], data_roots(Env)).

eleveldb_data_roots_test() ->
    Env = [{riak_kv, [{storage_backend, riak_kv_eleveldb_backend}]},
           {eleveldb, [{data_root, "/var/lib/riak/leveldb"}]}],
    ?assertEqual(["/var/lib/riak/leveldb"], data_roots(Env)).

cs_multi_backend_data_roots_test() ->
    Env = [{riak_kv, [{storage_backend, riak_cs_kv_multi_backend},
                      {multi_backend, [
                            {be_default, riak_kv_eleveldb_backend, [
                                    {cache_size, 47721858},
                                    {data_root, "/var/lib/riak/leveldb"},
                                    {max_open_files, 50}
                                    ]},
                            {be_blocks, riak_kv_bitcask_backend, [
                                    {data_root, "/var/lib/riak/bitcask"}
                                    ]}
                            ]}]},
           {eleveldb, [{data_root, "/var/lib/riak/leveldb"}]}],
    ?assertEqual(["/var/lib/riak/leveldb"], data_roots(Env)).

kv_multi_backend_data_roots_test() ->
    Env = [{riak_kv, [{storage_backend, riak_cs_kv_multi_backend},
                      {multi_backend, [
                            {first_backend, riak_kv_eleveldb_backend, [
                                    {cache_size, 47721858},
                                    {data_root, "leveldb1"},
                                    {max_open_files, 50}
                                    ]},
                            {second_backend, riak_kv_eleveldb_backend, [
                                    {data_root, "leveldb2"}
                                    ]}
                            ]}]},
           {eleveldb, [{data_root, "/var/lib/riak/leveldb"}]}],
    ?assertEqual(["leveldb1", "leveldb2"], lists:sort(data_roots(Env))).

-endif.
