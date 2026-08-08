-module(aarondb_mcp_stdio_ffi).
-export([get_line/1]).

get_line(Prompt) ->
    case io:get_line(Prompt) of
        eof -> {error, nil};
        {error, _Reason} -> {error, nil};
        Line -> {ok, unicode:characters_to_binary(Line)}
    end.
