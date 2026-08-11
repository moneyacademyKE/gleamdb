-module(aarondb_envelope_ffi).
-export([sha256/1, ed25519_sign/2, ed25519_verify/3, ed25519_public_key/1]).

sha256(Data) when is_binary(Data) ->
    crypto:hash(sha256, Data).

%% OTP's eddsa private-key form is the documented 32-byte Ed25519 seed or the
%% 64-byte private key returned by crypto:generate_key/2. Gleam exposes bytes;
%% this FFI intentionally neither parses terms nor invents key formats.
ed25519_sign(Data, PrivateKey) when is_binary(Data), is_binary(PrivateKey) ->
    crypto:sign(eddsa, none, Data, [PrivateKey, ed25519]).

ed25519_verify(Data, Signature, PublicKey)
    when is_binary(Data), is_binary(Signature), is_binary(PublicKey) ->
    try crypto:verify(eddsa, none, Data, Signature, [PublicKey, ed25519]) of
        Result -> Result
    catch
        error:_ -> false
    end.

ed25519_public_key(PrivateKey) when is_binary(PrivateKey) ->
    case byte_size(PrivateKey) of
        32 ->
            {PublicKey, _PrivateKey} = crypto:generate_key(eddsa, ed25519, PrivateKey),
            PublicKey;
        64 ->
            %% OTP represents a private key as seed || public key.
            binary:part(PrivateKey, 32, 32)
    end.
