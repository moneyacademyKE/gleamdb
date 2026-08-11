-module(aarondb_raft_durability_ffi).
-export([
    save/3, load/1, backup/2, remove/1, overwrite_for_test/2,
    interrupt_before_rename_for_test/2
]).

%% The binary includes a magic/version envelope and a SHA-256 over the exact
%% Erlang external-term payload. We write a sibling temporary file, fsync it,
%% rename atomically, then fsync the parent directory. A crash can produce the
%% old complete image or the new complete image—never an acknowledged partial.

-define(MAGIC, <<"AARONDB_RAFT_DURABILITY_V1\n">>).

save(Path, Persisted, StateImage) when is_binary(Path), is_binary(StateImage) ->
    Payload = term_to_binary({Persisted, StateImage}, [deterministic]),
    Bytes = envelope(Payload),
    Temp = <<Path/binary, ".tmp">>,
    case file:write_file(Temp, Bytes, [binary, raw]) of
        ok ->
            case sync_rename(Temp, Path) of
                ok -> {ok, nil};
                {error, Reason} ->
                    _ = file:delete(Temp),
                    {error, format_error(Reason)}
            end;
        {error, Reason} -> {error, format_error(Reason)}
    end;
save(_, _, _) -> {error, <<"invalid durability save arguments">>}.

load(Path) when is_binary(Path) ->
    case file:read_file(Path) of
        {ok, Bytes} -> decode(Bytes);
        {error, enoent} -> {error, {io, <<"not_found">>}};
        {error, Reason} -> {error, {io, format_error(Reason)}}
    end;
load(_) -> {error, {io, <<"invalid durability path">>}}.

backup(Path, Destination) when is_binary(Path), is_binary(Destination) ->
    case load(Path) of
        {ok, _} ->
            case file:read_file(Path) of
                {ok, Bytes} -> atomic_write(Destination, Bytes);
                {error, Reason} -> {error, format_error(Reason)}
            end;
        {error, {corrupt, Reason}} -> {error, <<"refusing backup of corrupt store: ", Reason/binary>>};
        {error, {io, Reason}} -> {error, Reason}
    end;
backup(_, _) -> {error, <<"invalid backup arguments">>}.

remove(Path) when is_binary(Path) ->
    case file:delete(Path) of
        ok -> {ok, nil};
        {error, enoent} -> {ok, nil};
        {error, Reason} -> {error, format_error(Reason)}
    end;
remove(_) -> {error, <<"invalid durability path">>}.

overwrite_for_test(Path, Bytes) when is_binary(Path), is_binary(Bytes) ->
    case file:write_file(Path, Bytes, [binary, raw]) of
        ok -> {ok, nil};
        {error, Reason} -> {error, format_error(Reason)}
    end;
overwrite_for_test(_, _) -> {error, <<"invalid durability overwrite arguments">>}.

%% Models process death after a synced temporary write but before atomic rename.
%% It deliberately leaves the acknowledged primary untouched; callers must
%% recover the old complete image, not observe the staged partial bytes.
interrupt_before_rename_for_test(Path, PartialBytes)
  when is_binary(Path), is_binary(PartialBytes) ->
    Temp = <<Path/binary, ".tmp">>,
    case file:write_file(Temp, PartialBytes, [binary, raw]) of
        ok ->
            case file:open(Temp, [read, raw, binary]) of
                {ok, Device} ->
                    Sync = file:sync(Device),
                    _ = file:close(Device),
                    case Sync of
                        ok -> {ok, nil};
                        {error, Reason} -> {error, format_error(Reason)}
                    end;
                {error, Reason} -> {error, format_error(Reason)}
            end;
        {error, Reason} -> {error, format_error(Reason)}
    end;
interrupt_before_rename_for_test(_, _) ->
    {error, <<"invalid interrupted durability write arguments">>}.

atomic_write(Path, Bytes) ->
    Temp = <<Path/binary, ".tmp">>,
    case file:write_file(Temp, Bytes, [binary, raw]) of
        ok ->
            case sync_rename(Temp, Path) of
                ok -> {ok, nil};
                {error, Reason} ->
                    _ = file:delete(Temp),
                    {error, format_error(Reason)}
            end;
        {error, Reason} -> {error, format_error(Reason)}
    end.

sync_rename(Temp, Path) ->
    case file:open(Temp, [read, raw, binary]) of
        {ok, Device} ->
            Sync = file:sync(Device),
            _ = file:close(Device),
            case Sync of
                ok ->
                    case file:rename(Temp, Path) of
                        ok -> sync_parent(Path);
                        {error, Reason} -> {error, Reason}
                    end;
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} -> {error, Reason}
    end.

%% Directory fsync is not supported by all OTP/filesystem combinations (macOS
%% often returns eisdir). The data file has already been fsynced; rename is
%% atomic. Treat unsupported directory sync as an explicit platform constraint,
%% not as a failed write.
sync_parent(Path) ->
    Directory = filename:dirname(binary_to_list(Path)),
    case file:open(Directory, [read, raw]) of
        {ok, Device} ->
            Sync = file:sync(Device),
            _ = file:close(Device),
            case Sync of
                ok -> ok;
                {error, eisdir} -> ok;
                {error, enotsup} -> ok;
                {error, Reason} -> {error, Reason}
            end;
        {error, eisdir} -> ok;
        {error, enotsup} -> ok;
        {error, Reason} -> {error, Reason}
    end.

envelope(Payload) ->
    Digest = crypto:hash(sha256, Payload),
    <<?MAGIC/binary, Digest/binary, Payload/binary>>.

decode(<<Magic:27/binary, Digest:32/binary, Payload/binary>>) ->
    case Magic =:= ?MAGIC andalso crypto:hash(sha256, Payload) =:= Digest of
        false -> {error, {<<"corrupt">>, <<"checksum mismatch">>}};
        true -> decode_payload(Payload)
    end;
decode(_) -> {error, {<<"corrupt">>, <<"invalid durability envelope">>}}.

decode_payload(Payload) ->
    try binary_to_term(Payload, [safe]) of
        {Persisted, StateImage} when is_binary(StateImage) -> {ok, {Persisted, StateImage}};
        _ -> {error, {<<"corrupt">>, <<"invalid durability payload">>}}
    catch
        error:badarg -> {error, {<<"corrupt">>, <<"invalid durability term">>}}
    end.

format_error(Reason) -> list_to_binary(io_lib:format("~p", [Reason])).
