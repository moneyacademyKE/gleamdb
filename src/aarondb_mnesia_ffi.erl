-module(aarondb_mnesia_ffi).
-export([init/0, persist/1, persist_batch/1, recover/0, select/1]).

init() ->
    case mnesia:system_info(is_running) of
        yes -> ok;
        _ ->
            _ = mnesia:create_schema([node()]),
            application:ensure_all_started(mnesia)
    end,

    ExpectedAttrs = [entity, attribute, value, tx, tx_index, valid_time, operation],
    case table_attributes(datoms) of
        {ok, ExpectedAttrs} ->
            {ok, nil};
        {ok, ActualAttrs} ->
            {error, schema_mismatch_message(ExpectedAttrs, ActualAttrs)};
        missing ->
            create_datoms_table(ExpectedAttrs)
    end.

table_attributes(Table) ->
    try mnesia:table_info(Table, attributes) of
        Attrs -> {ok, Attrs}
    catch
        exit:{aborted, _} -> missing
    end.

create_datoms_table(ExpectedAttrs) ->
    case mnesia:create_table(datoms, [
        {record_name, datom},
        {attributes, ExpectedAttrs},
        {disc_copies, [node()]}
    ]) of
        {atomic, ok} ->
            wait_for_datoms();
        {aborted, {already_exists, datoms}} ->
            %% A concurrent initializer may have created it; inspect rather than
            %% assuming its schema matches.
            case table_attributes(datoms) of
                {ok, ExpectedAttrs} -> wait_for_datoms();
                {ok, ActualAttrs} -> {error, schema_mismatch_message(ExpectedAttrs, ActualAttrs)};
                missing -> {error, <<"datoms table disappeared during initialization">>}
            end;
        {aborted, Reason} ->
            {error, list_to_binary(io_lib:format("failed to create datoms table: ~p", [Reason]))}
    end.

wait_for_datoms() ->
    case mnesia:wait_for_tables([datoms], 5000) of
        ok -> {ok, nil};
        {timeout, Tables} ->
            {error, list_to_binary(io_lib:format("timed out waiting for Mnesia tables: ~p", [Tables]))};
        {error, Reason} ->
            {error, list_to_binary(io_lib:format("failed waiting for Mnesia tables: ~p", [Reason]))}
    end.

schema_mismatch_message(ExpectedAttrs, ActualAttrs) ->
    list_to_binary(
        io_lib:format(
            "datoms schema mismatch; expected ~p, found ~p. No data was modified. Create a backup, migrate explicitly, or reset the table deliberately.",
            [ExpectedAttrs, ActualAttrs]
        )
    ).

persist(Datom) ->
    mnesia:dirty_write(datoms, Datom),
    nil.

persist_batch(Datoms) ->
    F = fun() ->
        lists:foreach(fun(D) -> mnesia:write(datoms, D, write) end, Datoms)
    end,
    mnesia:transaction(F),
    nil.

recover() ->
    F = fun() ->
        mnesia:match_object(datoms, {datom, '_', '_', '_', '_', '_', '_', '_'}, read)
    end,
    case mnesia:transaction(F) of
        {atomic, Records} -> {ok, Records};
        {aborted, Reason} -> {error, list_to_binary(io_lib:format("~p", [Reason]))}
    end.

select(Pattern) ->
    {E, A, V} = Pattern,
    MatchE = case E of {uid, {entity_id, Eid}} -> Eid; _ -> '_' end,
    MatchA = A, % A is already a binary in Erlang from Gleam String
    MatchV = case V of {val, Val} -> Val; _ -> '_' end,

    MS = {datom, MatchE, MatchA, MatchV, '_', '_', '_', '_'},
    F = fun() -> mnesia:match_object(datoms, MS, read) end,
    case mnesia:transaction(F) of
        {atomic, Records} -> {ok, Records};
        {aborted, Reason} -> {error, list_to_binary(io_lib:format("~p", [Reason]))}
    end.
