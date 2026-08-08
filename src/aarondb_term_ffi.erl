-module(aarondb_term_ffi).
-export([decode_rule/1, decode_term/1]).

%% Decode Erlang external-term data without allowing new atom creation. All
%% decoder failures are converted to Gleam's Result error shape.
decode_rule(Binary) ->
    case safe_decode(Binary) of
        {ok, {rule, Head, Body} = Rule} when is_tuple(Head), tuple_size(Head) =:= 3, is_list(Body) ->
            {ok, Rule};
        _ ->
            {error, nil}
    end.

decode_term(Binary) ->
    safe_decode(Binary).

safe_decode(Binary) ->
    try binary_to_term(Binary, [safe]) of
        Term -> {ok, Term}
    catch
        error:badarg -> {error, nil};
        _:_ -> {error, nil}
    end.
