-module(aarondb_cluster_transport_ffi).
-include_lib("kernel/include/file.hrl").
-export([
    gateway_metrics/1,
    node_metrics/0,
    start_gateway/3,
    stop_gateway/2,
    lookup_gateway/2,
    lookup_gateway_name/1,
    lookup_runtime/2,
    gateway_call/2,
    receive_frame/3,
    join_peer/3,
    elect_leader/3,
    replicate_command/3,
    inspect_runtime/2,
    stop_runtime/2
]).

%% The gateway owns the untyped distributed-PID boundary. A Gleam runtime
%% subject is `{subject, Pid, Tag}`; raw remote callers must be wrapped with
%% that Tag before reaching the generated actor selector. Reply subjects travel
%% unchanged, preserving the typed reply channel selected by the caller.
%% Gateways are node-local. `global` is intentionally avoided: a controller
%% connected to several peers can trigger its overlapping-partition resolver,
%% which is the opposite of a transport registry.
start_gateway(Cluster, Node, Runtime = {subject, _Pid, _Tag}) ->
    Name = registry_name(Cluster, Node),
    Key = registry_key(Name),
    RuntimeKey = runtime_key(Name),
    case persistent_term:get(Key, undefined) of
        undefined ->
            %% `actor.start/1` links its child to the process that invoked
            %% `cluster_runtime.start/1`. In the integration runner that
            %% invoker is a short-lived `rpc` worker; retain no death-link to
            %% that request process or the runtime dies after the RPC returns.
            unlink(subject_pid(Runtime)),
            Gateway = spawn(fun() -> gateway_loop(Runtime) end),
            persistent_term:put(Key, Gateway),
            persistent_term:put(RuntimeKey, Runtime),
            %% Same-VM Gleam clients retain their existing lookup surface.
            %% Cross-VM traffic never resolves this global name; it uses
            %% target-node-local `persistent_term` through authenticated RPC.
            _ = global:register_name(Name, Gateway),
            {ok, nil};
        _ ->
            {error, nil}
    end;
start_gateway(_Cluster, _Node, _Runtime) ->
    {error, nil}.

stop_gateway(Cluster, Node) ->
    Name = registry_name(Cluster, Node),
    Key = registry_key(Name),
    RuntimeKey = runtime_key(Name),
    case persistent_term:get(Key, undefined) of
        undefined -> nil;
        Pid ->
            persistent_term:erase(Key),
            persistent_term:erase(RuntimeKey),
            _ = global:unregister_name(Name),
            Pid ! stop,
            nil
    end.

%% Kept for local callers; remote callers execute this lookup on the owning node
%% through authenticated `rpc:call/5`.
lookup_gateway(Cluster, Node) ->
    lookup_gateway_name(registry_name(Cluster, Node)).

lookup_gateway_name(Name) ->
    persistent_term:get(registry_key(Name), undefined).

gateway_metrics(Pid) when is_pid(Pid) ->
    case process_info(Pid, [message_queue_len, memory]) of
        undefined -> {error, gateway_unavailable};
        Metrics -> {ok, Metrics}
    end;
gateway_metrics(_Pid) ->
    {error, gateway_unavailable}.

%% Resource data is sampled inside each peer VM rather than inferred from the
%% controller. Disk usage includes the node's Mnesia directory when present and
%% the process count provides a bounded proxy for runtime population.
node_metrics() ->
    #{
        process_count => erlang:system_info(process_count),
        total_memory_bytes => erlang:memory(total),
        mnesia_disk_bytes => directory_bytes(mnesia:system_info(directory))
    }.

directory_bytes(Dir) when is_list(Dir) ->
    case filelib:is_dir(Dir) of
        true -> lists:sum([Size || File <- filelib:fold_files(Dir, ".*", true, fun(Path, Acc) -> [Path | Acc] end, []), {ok, #file_info{size = Size}} <- [file:read_file_info(File)]]);
        false -> 0
    end;
directory_bytes(_) -> 0.

lookup_runtime(Cluster, Node) ->
    persistent_term:get(runtime_key(registry_name(Cluster, Node)), {error, nil}).

%% Synchronous raw edge used by the black-box integration runner. The gateway
%% creates the typed response Subject itself, so the Gleam actor only ever sees
%% a local, capability-valid reply handle. The caller receives a correlation-ref
%% response rather than a forged Subject.
gateway_call(Pid, Request) when is_pid(Pid) ->
    Ref = make_ref(),
    Pid ! {gateway_call, self(), Ref, Request},
    receive
        {Ref, Result} -> Result
    after 6000 ->
        {error, {gateway_timeout, Request}}
    end;
gateway_call(_Pid, _Request) ->
    {error, gateway_unavailable}.

gateway_loop(Runtime) ->
    receive
        stop -> ok;
        {gateway_call, From, Ref, Request} ->
            %% Keep the correlation owner as the gateway process itself. The
            %% prior worker hop was needless and made the black-box RPC return
            %% depend on a second, unobserved mailbox.
            run_call(Runtime, From, Ref, Request),
            gateway_loop(Runtime);
        {receive_frame, Frame, Reply} ->
            forward(Runtime, {'receive', Frame, Reply}),
            gateway_loop(Runtime);
        {join_peer, Peer, Reply} ->
            forward(Runtime, {join, Peer, Reply}),
            gateway_loop(Runtime);
        {elect_leader, Votes, Reply} ->
            forward(Runtime, {elect, Votes, Reply}),
            gateway_loop(Runtime);
        {replicate_command, Command, Reply} ->
            forward(Runtime, {replicate, Command, Reply}),
            gateway_loop(Runtime);
        {inspect_runtime, Reply} ->
            forward(Runtime, {inspect, Reply}),
            gateway_loop(Runtime);
        {stop_runtime, Reply} ->
            forward(Runtime, {stop, Reply}),
            ok;
        _Unexpected ->
            gateway_loop(Runtime)
    end.

run_call(Runtime = {subject, _Pid, _Tag}, From, Ref, Request) ->
    %% `process.send/2` sends `{Tag, Message}` and the tag is a reference.
    %% A reference created in this process survives intact through the actor
    %% mailbox; wait for that exact envelope rather than matching an invented
    %% `{ReplyTag, Result}` shape after a previous relay stripped it.
    ReplyTag = make_ref(),
    Reply = {subject, self(), ReplyTag},
    case request_message(Request, Reply) of
        {ok, Message} ->
            forward(Runtime, Message),
            receive
                {ReplyTag, Result} ->
                    From ! {Ref, Result}
            after 4000 ->
                From ! {Ref, {error, {gateway_timeout, Request, process_info(_Pid, [current_function, message_queue_len, messages, status]), process_info(self(), [current_function, message_queue_len, messages])}}}
            end;
        error ->
            From ! {Ref, {error, {invalid_gateway_request, Request}}}
    end.

request_message({receive_frame, Frame}, Reply) -> {ok, {'receive', Frame, Reply}};
request_message({join_peer, Peer}, Reply) -> {ok, {join, Peer, Reply}};
request_message({elect_leader, Votes}, Reply) -> {ok, {elect, Votes, Reply}};
request_message({replicate_command, Command}, Reply) -> {ok, {replicate, Command, Reply}};
request_message(inspect_runtime, Reply) -> {ok, {inspect, Reply}};
request_message(stop_runtime, Reply) -> {ok, {stop, Reply}};
request_message(_, _) -> error.

forward({subject, Pid, Tag}, Message) ->
    Pid ! {Tag, Message},
    nil.

receive_frame(Pid, Frame, Reply) -> send(Pid, {receive_frame, Frame, Reply}).
join_peer(Pid, Peer, Reply) -> send(Pid, {join_peer, Peer, Reply}).
elect_leader(Pid, Votes, Reply) -> send(Pid, {elect_leader, Votes, Reply}).
replicate_command(Pid, Command, Reply) -> send(Pid, {replicate_command, Command, Reply}).
inspect_runtime(Pid, Reply) -> send(Pid, {inspect_runtime, Reply}).
stop_runtime(Pid, Reply) -> send(Pid, {stop_runtime, Reply}).

send(Pid, Message) when is_pid(Pid) ->
    Pid ! Message,
    nil;
send(_Pid, _Message) -> nil.

subject_pid({subject, Pid, _Tag}) -> Pid.

registry_name(Cluster, Node) ->
    list_to_binary(["aarondb.cluster.", Cluster, ".", Node]).

runtime_key(Name) ->
    {aarondb_cluster_runtime, Name}.

registry_key(Name) ->
    {aarondb_cluster_gateway, Name}.


