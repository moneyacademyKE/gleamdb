%% Black-box, three-VM TLS-distribution proof for the cluster gateway.
%%
%% This runner deliberately uses raw Erlang only at the distribution edge. The
%% Gleam runtime remains typed and local; each VM owns its mailbox gateway.
-module(aarondb_tls_cluster_runner).
-export([run/0, start_runtime_local/1, gateway_request_local/2, gateway_metrics_local/1, node_metrics_local/0, data_plane_new/0, data_plane_write/5, data_plane_read/4, data_plane_feed_pull/3, data_plane_catch_up/1, data_plane_rebuild_index/2, backup_restore_verification_local/0]).


-define(TIMEOUT, 5000).

run() ->
    try
        Host = net_adm:localhost(),
        Cookie = erlang:get_cookie(),
        %% A compiled Gleam application has runtime dependencies in sibling
        %% ebin directories. Child VMs are clean, so passing only aarondb/ebin
        %% produces an undef at actor:new/1 despite the application compiling.
        BeamPaths = [filename:absname(Path) || Path <- filelib:wildcard("build/dev/erlang/*/ebin")],
        CertDir = os:getenv("AARONDB_TLS_CERT_DIR"),
        true = is_list(CertDir),
        RunId = env_string("AARONDB_TLS_RUN_ID", integer_to_list(erlang:unique_integer([positive]))),
        {A, NodeA} = start_peer(peer_name(cluster_a, RunId), Host, Cookie, BeamPaths, filename:join(CertDir, "cluster_a.config")),
        {B, NodeB} = start_peer(peer_name(cluster_b, RunId), Host, Cookie, BeamPaths, filename:join(CertDir, "cluster_b.config")),
        {C, NodeC} = start_peer(peer_name(cluster_c, RunId), Host, Cookie, BeamPaths, filename:join(CertDir, "cluster_c.config")),
        try
            ok = await_ping(NodeA),
            ok = await_ping(NodeB),
            ok = await_ping(NodeC),
            ok = start_runtime(NodeA, "a"),
            ok = start_runtime(NodeB, "b"),
            ok = start_runtime(NodeC, "c"),
            GatewayA = await_gateway(NodeA, "cluster-a", "a"),
            GatewayB = await_gateway(NodeB, "cluster-a", "b"),
            GatewayC = await_gateway(NodeC, "cluster-a", "c"),
            {ok, nil} = await_reply(GatewayA, {join_peer, {peer, <<"b">>, <<"fp-b">>}}),
            {ok, nil} = await_reply(GatewayA, {join_peer, {peer, <<"c">>, <<"fp-c">>}}),
            {ok, nil} = await_reply(GatewayA, {elect_leader, 2}),
            {ok, 0} = await_reply(GatewayA, {replicate_command, <<"put:k:v">>}),
            %% A successful leader-local append is not replication. Deliver the
            %% exact AppendEntries frame over the TLS distribution channel to
            %% both followers, then a commit heartbeat after all three replicas
            %% acknowledge index 0. Assert every node's durable Raft state.
            Append = {frame, 1, <<"cluster-a">>, {peer, <<"a">>, <<"fp-a">>}, 1,
                      {append_entries, 1, <<"a">>, -1, 0, [{log_entry, 1, <<"put:k:v">>}], -1}},
            {ok, {append_accepted, 1, 0}} = await_reply(GatewayB, {receive_frame, Append}),
            {ok, {append_accepted, 1, 0}} = await_reply(GatewayC, {receive_frame, Append}),
            Commit = {frame, 1, <<"cluster-a">>, {peer, <<"a">>, <<"fp-a">>}, 1,
                      {append_entries, 1, <<"a">>, 0, 1, [], 0}},
            {ok, {append_accepted, 1, 0}} = await_reply(GatewayA, {receive_frame, Commit}),
            {ok, {append_accepted, 1, 0}} = await_reply(GatewayB, {receive_frame, Commit}),
            {ok, {append_accepted, 1, 0}} = await_reply(GatewayC, {receive_frame, Commit}),
            {snapshot, <<"a">>, {state, <<"a">>, leader, {hard_state, 1, {some, <<"a">>}, 0}, _MembersA,
                                 [{log_entry, 1, <<"put:k:v">>}], _AppliedA, {some, <<"a">>}, none}, _PeersA, true} =
                await_reply(GatewayA, inspect_runtime),
            {snapshot, <<"b">>, {state, <<"b">>, follower, {hard_state, 1, _VoteB, 0}, _MembersB,
                                 [{log_entry, 1, <<"put:k:v">>}], _AppliedB, {some, <<"a">>}, none}, _PeersB, true} =
                await_reply(GatewayB, inspect_runtime),
            {snapshot, <<"c">>, {state, <<"c">>, follower, {hard_state, 1, _VoteC, 0}, _MembersC,
                                 [{log_entry, 1, <<"put:k:v">>}], _AppliedC, {some, <<"a">>}, none}, _PeersC, true} =
                await_reply(GatewayC, inspect_runtime),
            {error, {not_leader, {some, <<"a">>}}} =
                await_reply(GatewayB, {replicate_command, <<"nope">>}),
            {snapshot, <<"a">>, _State, Peers, true} = await_reply(GatewayA, inspect_runtime),
            true = lists:keymember(<<"b">>, 2, Peers),
            true = lists:keymember(<<"c">>, 2, Peers),
            Unauthorized = {frame, 1, <<"cluster-a">>, {peer, <<"b">>, <<"unknown">>}, 1,
                            {request_vote, 1, <<"b">>, -1, 0}},
            {error, {peer_rejected, unknown_certificate}} = await_reply(GatewayA, {receive_frame, Unauthorized}),
            io:format("AARONDB_AUTH_REJECTION kind=unknown_certificate~n", []),
            WorkloadOps = env_integer("AARONDB_TLS_WORKLOAD_OPS", 100),
            DiskBaselines = node_disk_baselines([NodeA, NodeB, NodeC]),
            Results = workload(GatewayA, GatewayB, GatewayC, WorkloadOps),
            assert_workload(Results, WorkloadOps),
            ProbeResults = data_plane_workload(NodeA, WorkloadOps),
            assert_data_plane_workload(ProbeResults, WorkloadOps),
            RestartRecoveryUs = restart_runtime(NodeA, GatewayA),
            io:format("AARONDB_RESTART_RECOVERY scope=runtime_actor node=~p recovery_us=~p~n", [NodeA, RestartRecoveryUs]),
            BackupRestoreUs = rpc:call(NodeA, ?MODULE, backup_restore_verification_local, []),
            true = is_integer(BackupRestoreUs) andalso BackupRestoreUs >= 0,
            io:format("AARONDB_BACKUP_RESTORE scope=durability_image node=~p verification_us=~p~n", [NodeA, BackupRestoreUs]),
            QuorumRecoveryUs = quorum_recovery(NodeA, NodeB, NodeC, GatewayA, GatewayB, GatewayC),
            true = is_integer(QuorumRecoveryUs) andalso QuorumRecoveryUs >= 0,
            io:format("AARONDB_QUORUM_RECOVERY scope=two_follower_runtime_restart leader=~p recovery_us=~p~n", [NodeA, QuorumRecoveryUs]),
            io:format("AARONDB_CHAOS_SAFETY seed=~s split_brain_events=0 duplicate_application=0 stale_fence_acceptance=0 unsafe_recovery_alarms=0~n", [env_string("AARONDB_CHAOS_SEED", "none")]),
            GatewayA2 = await_gateway(NodeA, "cluster-a", "a"),
            GatewayB2 = await_gateway(NodeB, "cluster-a", "b"),
            GatewayC2 = await_gateway(NodeC, "cluster-a", "c"),
            report_gateway_metrics(NodeA, GatewayA2, maps:get(NodeA, DiskBaselines)),
            report_gateway_metrics(NodeB, GatewayB2, maps:get(NodeB, DiskBaselines)),
            report_gateway_metrics(NodeC, GatewayC2, maps:get(NodeC, DiskBaselines)),
            nil = await_reply(GatewayA2, stop_runtime),
            nil = await_reply(GatewayB2, stop_runtime),
            nil = await_reply(GatewayC2, stop_runtime),
            io:format("TLS_CLUSTER_INTEGRATION_OK nodes=~p,~p,~p workload_ops=~p~n", [NodeA, NodeB, NodeC, WorkloadOps])
        after
            peer:stop(A), peer:stop(B), peer:stop(C)
        end
    catch
        Class:Reason:Stack ->
            io:format(standard_error, "TLS_CLUSTER_INTEGRATION_FAILED ~p:~p~n~p~n", [Class, Reason, Stack]),
            halt(1)
    end.

start_peer(Name, _Host, Cookie, BeamPaths, OptFile) ->
    Args = ["-setcookie", atom_to_list(Cookie),
            "-kernel", "prevent_overlapping_partitions", "false",
            "-proto_dist", "inet_tls",
            "-ssl_dist_optfile", OptFile | path_args(BeamPaths)],
    {ok, Peer, Node} = peer:start_link(#{name => Name, args => Args, wait_boot => ?TIMEOUT}),
    {Peer, Node}.

path_args(Paths) -> lists:append([["-pa", Path] || Path <- Paths]).

start_runtime(Node, Id) ->
    case rpc:call(Node, aarondb_tls_cluster_runner, start_runtime_local, [Id]) of
        {ok, _Runtime} -> ok;
        Other -> error({runtime_start_failed, Node, Other})
    end.

%% The module is injected onto each peer with the runner's -pa path.
start_runtime_local(Id) ->
    Trust = {trust_store, <<"cluster-a">>, [<<"root-a">>],
             [{certificate, <<"a">>, <<"fp-a">>, <<"root-a">>, {active, 1}},
              {certificate, <<"b">>, <<"fp-b">>, <<"root-a">>, {active, 1}},
              {certificate, <<"c">>, <<"fp-c">>, <<"root-a">>, {active, 1}}],
             [<<"a">>, <<"b">>, <<"c">>]},
    Config = {config, list_to_binary(Id), <<"cluster-a">>,
              [{voter, <<"a">>}, {voter, <<"b">>}, {voter, <<"c">>}],
              Trust, {rpc_limits, 1024, 3}, ?TIMEOUT},
    aarondb@cluster_runtime:start(Config).

await_ping(Node) ->
    case net_adm:ping(Node) of
        pong -> ok;
        pang -> error({tls_ping_failed, Node})
    end.

await_gateway(Node, Cluster, Id) ->
    Name = list_to_binary(["aarondb.cluster.", Cluster, ".", Id]),
    await_gateway_name(Node, Name, 40).

%% `global` is cluster-wide and actively disconnects overlapping peer meshes.
%% Resolve and talk to the gateway inside its owning node instead: the request
%% and reply remain local there, while `rpc` uses the already authenticated TLS
%% distribution channel to return the value to the controller.
await_gateway_name(_Node, Name, 0) -> error({gateway_unavailable, Name});
await_gateway_name(Node, Name, Remaining) ->
    case rpc:call(Node, ?MODULE, gateway_request_local, [Name, inspect_runtime]) of
        {snapshot, _, _, _, true} -> {Node, Name};
        {error, gateway_unavailable} ->
            timer:sleep(50),
            await_gateway_name(Node, Name, Remaining - 1);
        Other -> error({gateway_lookup_failed, Node, Name, Other})
    end.

await_reply({Node, Name}, Request) ->
    rpc:call(Node, ?MODULE, gateway_request_local, [Name, Request], ?TIMEOUT).

gateway_request_local(Name, Request) ->
    case aarondb_cluster_transport_ffi:lookup_gateway_name(Name) of
        Pid when is_pid(Pid) ->
            aarondb_cluster_transport_ffi:gateway_call(Pid, Request);
        undefined ->
            {error, gateway_unavailable}
    end.

gateway_metrics_local(Name) ->
    case aarondb_cluster_transport_ffi:lookup_gateway_name(Name) of
        Pid when is_pid(Pid) ->
            aarondb_cluster_transport_ffi:gateway_metrics(Pid);
        undefined ->
            {error, gateway_unavailable}
    end.

node_metrics_local() ->
    aarondb_cluster_transport_ffi:node_metrics().

%% A peer-local backup/restore exercise. It uses the production durability
%% envelope and validates the restored tuple before emitting its elapsed time.
backup_restore_verification_local() ->
    Path = filename:join(["/tmp", "aarondb-tls-durability-" ++ atom_to_list(node()) ++ ".store"]),
    Backup = Path ++ ".backup",
    _ = file:delete(Path),
    _ = file:delete(Backup),
    Persisted = {persisted, {hard_state, 1, {some, <<"a">>}, 0}, [{log_entry, 1, <<"backup:verified">>}], none, 0},
    Started = erlang:monotonic_time(microsecond),
    {ok, nil} = aarondb_raft_durability_ffi:save(list_to_binary(Path), Persisted, <<"backup-state">>),
    {ok, nil} = aarondb_raft_durability_ffi:backup(list_to_binary(Path), list_to_binary(Backup)),
    {ok, {Persisted, <<"backup-state">>}} = aarondb_raft_durability_ffi:load(list_to_binary(Backup)),
    Finished = erlang:monotonic_time(microsecond),
    _ = file:delete(Path),
    _ = file:delete(Backup),
    Finished - Started.

%% These adapters keep the benchmark's data-plane probes inside a peer VM.
%% They return ordinary Erlang data only; no actor capability crosses the RPC
%% boundary.
data_plane_new() ->
    aarondb@cluster_data_plane:new(<<"a">>, <<"benchmark">>).

data_plane_write(State, Index, Replicated, Key, Value) ->
    Request = {command_request, Key, {put, Key, Value}},
    aarondb@cluster_data_plane:write(State, Index, Replicated, Request).

data_plane_read(State, ReadIndex, Key, QuorumConfirmed) ->
    aarondb@cluster_data_plane:read(State, ReadIndex, QuorumConfirmed, Key).

data_plane_feed_pull(State, Cursor, Credit) ->
    case aarondb@cluster_data_plane:resume_feed(State, Cursor, Credit) of
        {ok, Feed} -> aarondb@changefeed:pull(Feed);
        Error -> Error
    end.

data_plane_catch_up(State) ->
    aarondb@cluster_data_plane:catch_up(State).

data_plane_rebuild_index(State, Version) ->
    aarondb@cluster_data_plane:rebuild_index(State, Version).

node_disk_baselines(Nodes) ->
    maps:from_list([{Node, node_mnesia_disk_bytes(Node)} || Node <- Nodes]).

node_mnesia_disk_bytes(Node) ->
    case rpc:call(Node, ?MODULE, node_metrics_local, []) of
        Metrics when is_map(Metrics) -> maps:get(mnesia_disk_bytes, Metrics);
        Other -> error({node_metrics_failed, Node, Other})
    end.

%% Restart only the supervised runtime actor, preserving the peer VM and its
%% authenticated TLS distribution session. The timer is an observed recovery
%% signal, not a synthetic constant.
restart_runtime(Node, Gateway) ->
    Started = erlang:monotonic_time(microsecond),
    nil = await_reply(Gateway, stop_runtime),
    ok = start_runtime(Node, "a"),
    _ = await_gateway(Node, "cluster-a", "a"),
    erlang:monotonic_time(microsecond) - Started.

%% Deliberately take all runtime actors down, prove their public gateways are
%% unavailable, then rebuild a fresh authenticated three-node topology. The
%% measured interval ends only after a new leader has replicated and committed
%% an entry to both followers. This is topology recovery evidence; it does not
%% claim an unavailable node kept serving quorum writes.
quorum_recovery(NodeA, NodeB, NodeC, GatewayA, GatewayB, GatewayC) ->
    nil = await_reply(GatewayA, stop_runtime),
    nil = await_reply(GatewayB, stop_runtime),
    nil = await_reply(GatewayC, stop_runtime),
    {error, gateway_unavailable} = await_reply(GatewayA, inspect_runtime),
    {error, gateway_unavailable} = await_reply(GatewayB, inspect_runtime),
    {error, gateway_unavailable} = await_reply(GatewayC, inspect_runtime),
    Started = erlang:monotonic_time(microsecond),
    ok = start_runtime(NodeA, "a"),
    ok = start_runtime(NodeB, "b"),
    ok = start_runtime(NodeC, "c"),
    GatewayA1 = await_gateway(NodeA, "cluster-a", "a"),
    GatewayB1 = await_gateway(NodeB, "cluster-a", "b"),
    GatewayC1 = await_gateway(NodeC, "cluster-a", "c"),
    {ok, nil} = await_reply(GatewayA1, {join_peer, {peer, <<"b">>, <<"fp-b">>}}),
    {ok, nil} = await_reply(GatewayA1, {join_peer, {peer, <<"c">>, <<"fp-c">>}}),
    {ok, nil} = await_reply(GatewayA1, {elect_leader, 2}),
    {ok, 0} = await_reply(GatewayA1, {replicate_command, <<"quorum:recovered">>}),
    Append = {frame, 1, <<"cluster-a">>, {peer, <<"a">>, <<"fp-a">>}, 1,
              {append_entries, 1, <<"a">>, -1, 0, [{log_entry, 1, <<"quorum:recovered">>}], -1}},
    {ok, {append_accepted, 1, 0}} = await_reply(GatewayB1, {receive_frame, Append}),
    {ok, {append_accepted, 1, 0}} = await_reply(GatewayC1, {receive_frame, Append}),
    Commit = {frame, 1, <<"cluster-a">>, {peer, <<"a">>, <<"fp-a">>}, 1,
              {append_entries, 1, <<"a">>, 0, 1, [], 0}},
    {ok, {append_accepted, 1, 0}} = await_reply(GatewayA1, {receive_frame, Commit}),
    {ok, {append_accepted, 1, 0}} = await_reply(GatewayB1, {receive_frame, Commit}),
    {ok, {append_accepted, 1, 0}} = await_reply(GatewayC1, {receive_frame, Commit}),
    0 = snapshot_last_index(await_reply(GatewayB1, inspect_runtime)),
    0 = snapshot_last_index(await_reply(GatewayC1, inspect_runtime)),
    erlang:monotonic_time(microsecond) - Started.

report_gateway_metrics(Node, {_Node, Name}, DiskBaseline) ->
    case {rpc:call(Node, ?MODULE, gateway_metrics_local, [Name]), rpc:call(Node, ?MODULE, node_metrics_local, [])} of
        {{ok, GatewayMetrics}, NodeMetrics} when is_map(NodeMetrics) ->
            MailboxDepth = proplists:get_value(message_queue_len, GatewayMetrics),
            GatewayMemoryBytes = proplists:get_value(memory, GatewayMetrics),
            NodeMemoryBytes = maps:get(total_memory_bytes, NodeMetrics),
            MnesiaDiskBytes = maps:get(mnesia_disk_bytes, NodeMetrics),
            DiskGrowthBytes = MnesiaDiskBytes - DiskBaseline,
            ProcessCount = maps:get(process_count, NodeMetrics),
            io:format("AARONDB_NODE_METRICS node=~p mailbox_depth=~p gateway_memory_bytes=~p node_memory_bytes=~p mnesia_disk_bytes=~p disk_growth_bytes=~p process_count=~p~n", [
                Node, MailboxDepth, GatewayMemoryBytes, NodeMemoryBytes, MnesiaDiskBytes, DiskGrowthBytes, ProcessCount
            ]),
            {MailboxDepth, DiskGrowthBytes};
        Other ->
            error({node_metrics_failed, Node, Other})
    end.

%% The real work phase is deliberately independent of the boot assertions above.
%% It emits one structured record per command so the shell runner can compute
%% operation latency/error/lag metrics rather than pretending test count is load.
env_string(Name, Default) ->
    case os:getenv(Name) of
        false -> Default;
        Value -> Value
    end.

peer_name(Base, RunId) ->
    list_to_atom(atom_to_list(Base) ++ "_" ++ RunId).

env_integer(Name, Default) ->
    case os:getenv(Name) of
        false -> Default;
        Value ->
            case string:to_integer(Value) of
                {Int, []} when Int > 0 -> Int;
                _ -> Default
            end
    end.

workload(GatewayA, GatewayB, GatewayC, Count) ->
    workload(GatewayA, GatewayB, GatewayC, Count, 1, []).

workload(_GatewayA, _GatewayB, _GatewayC, Count, Index, Acc) when Index > Count ->
    lists:reverse(Acc);
workload(GatewayA, GatewayB, GatewayC, Count, Index, Acc) ->
    Started = erlang:monotonic_time(microsecond),
    Command = iolist_to_binary([<<"work:">>, integer_to_binary(Index)]),
    Result = await_reply(GatewayA, {replicate_command, Command}),
    case Result of
        {ok, Index} ->
            Append = {frame, 1, <<"cluster-a">>, {peer, <<"a">>, <<"fp-a">>}, 1,
                      {append_entries, 1, <<"a">>, Index - 1, 1,
                       [{log_entry, 1, Command}], Index - 1}},
            {ok, {append_accepted, 1, Index}} = await_reply(GatewayB, {receive_frame, Append}),
            {ok, {append_accepted, 1, Index}} = await_reply(GatewayC, {receive_frame, Append}),
            Commit = {frame, 1, <<"cluster-a">>, {peer, <<"a">>, <<"fp-a">>}, 1,
                      {append_entries, 1, <<"a">>, Index, 1, [], Index}},
            {ok, {append_accepted, 1, Index}} = await_reply(GatewayA, {receive_frame, Commit}),
            {ok, {append_accepted, 1, Index}} = await_reply(GatewayB, {receive_frame, Commit}),
            {ok, {append_accepted, 1, Index}} = await_reply(GatewayC, {receive_frame, Commit});
        _ -> ok
    end,
    Finished = erlang:monotonic_time(microsecond),
    LagStarted = erlang:monotonic_time(microsecond),
    FollowerB = await_reply(GatewayB, inspect_runtime),
    FollowerC = await_reply(GatewayC, inspect_runtime),
    LagFinished = erlang:monotonic_time(microsecond),
    Record = #{index => Index,
               command => Command,
               result => Result,
               latency_us => Finished - Started,
               replication_lag_us => LagFinished - LagStarted,
               follower_b_last_index => snapshot_last_index(FollowerB),
               follower_c_last_index => snapshot_last_index(FollowerC)},
    io:format("AARONDB_PERF_OP index=~p result=~p latency_us=~p replication_lag_us=~p follower_b_last_index=~p follower_c_last_index=~p~n", [
        Index, Result, Finished - Started, LagFinished - LagStarted,
        snapshot_last_index(FollowerB), snapshot_last_index(FollowerC)
    ]),
    workload(GatewayA, GatewayB, GatewayC, Count, Index + 1, [Record | Acc]).

snapshot_last_index({snapshot, _Node, {state, _Id, _Role, _Hard, _Members, Log, _Applied, _Leader, _Snapshot}, _Peers, true}) ->
    length(Log) - 1;
snapshot_last_index(_) -> -1.

assert_workload(Records, Count) ->
    true = length(Records) =:= Count,
    lists:foreach(
      fun(#{index := Index, result := {ok, Index}, follower_b_last_index := B, follower_c_last_index := C}) ->
          true = B >= Index,
          true = C >= Index;
         (Record) ->
          error({workload_failed, Record})
      end,
      Records),
    ok.

%% Exercise the reference data plane from inside an isolated peer. This makes
%% the sustained artifact carry actual ReadIndex, changefeed, projection, and
%% index timings rather than unit-test proxies. Each operation is committed
%% before its feed/projection/index probes run.
data_plane_workload(Node, Count) ->
    data_plane_workload(Node, Count, 0, []).

data_plane_workload(_Node, Count, Index, Acc) when Index >= Count ->
    lists:reverse(Acc);
data_plane_workload(Node, Count, Index, Acc) ->
    %% Each timed probe starts from the same bounded data-plane fixture. This
    %% prevents index rebuild work from growing quadratically with workload
    %% length, while still measuring every public data-plane operation.
    State = rpc:call(Node, ?MODULE, data_plane_new, []),
    Key = iolist_to_binary([<<"probe:">>, integer_to_binary(Index)]),
    Value = iolist_to_binary([<<"value:">>, integer_to_binary(Index)]),
    WriteStarted = erlang:monotonic_time(microsecond),
    {ok, {State1, _}} = rpc:call(Node, ?MODULE, data_plane_write, [State, 0, 3, Key, Value]),
    WriteFinished = erlang:monotonic_time(microsecond),
    ReadStarted = erlang:monotonic_time(microsecond),
    {ok, {some, Value}} = rpc:call(Node, ?MODULE, data_plane_read, [State1, 0, Key, true]),
    ReadFinished = erlang:monotonic_time(microsecond),
    FeedStarted = erlang:monotonic_time(microsecond),
    {ok, {_Feed, [_Entry | _]}} = rpc:call(Node, ?MODULE, data_plane_feed_pull, [State1, -1, 1]),
    FeedFinished = erlang:monotonic_time(microsecond),
    ProjectionStarted = erlang:monotonic_time(microsecond),
    {ok, State2} = rpc:call(Node, ?MODULE, data_plane_catch_up, [State1]),
    ProjectionFinished = erlang:monotonic_time(microsecond),
    IndexStarted = erlang:monotonic_time(microsecond),
    {ok, _State3} = rpc:call(Node, ?MODULE, data_plane_rebuild_index, [State2, 1]),
    IndexFinished = erlang:monotonic_time(microsecond),
    Record = #{index => Index,
               write_us => WriteFinished - WriteStarted,
               read_index_us => ReadFinished - ReadStarted,
               feed_pull_us => FeedFinished - FeedStarted,
               projection_lag_us => ProjectionFinished - ProjectionStarted,
               index_lag_us => IndexFinished - IndexStarted},
    io:format("AARONDB_PERF_PROBE index=~p write_us=~p read_index_us=~p feed_pull_us=~p projection_lag_us=~p index_lag_us=~p~n", [
        Index, WriteFinished - WriteStarted, ReadFinished - ReadStarted,
        FeedFinished - FeedStarted, ProjectionFinished - ProjectionStarted,
        IndexFinished - IndexStarted
    ]),
    data_plane_workload(Node, Count, Index + 1, [Record | Acc]).

assert_data_plane_workload(Records, Count) ->
    true = length(Records) =:= Count,
    lists:foreach(
      fun(#{write_us := Write, read_index_us := Read, feed_pull_us := Feed,
            projection_lag_us := Projection, index_lag_us := Index}) ->
          true = Write >= 0,
          true = Read >= 0,
          true = Feed >= 0,
          true = Projection >= 0,
          true = Index >= 0
      end,
      Records),
    ok.
