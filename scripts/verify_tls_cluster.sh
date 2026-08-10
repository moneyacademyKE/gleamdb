#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CERT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/aarondb-tls.XXXXXX")
cleanup() { rm -rf "$CERT_DIR"; }
trap cleanup EXIT INT TERM

# OTP's TLS distribution verifies both the certificate chain and the peer
# identity. A pile of self-signed leafs is not a CA, and it fails before the
# peer VM even finishes booting. Build a short-lived test CA and mTLS leafs
# with both client/server EKUs and every local connection name peer may use.
HOST_FQDN=$(hostname)
HOST_SHORT=$(hostname -s)
cat > "$CERT_DIR/leaf.ext" <<EOF
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=DNS:localhost,DNS:$HOST_SHORT,DNS:$HOST_FQDN,IP:127.0.0.1,IP:::1
EOF

openssl req -new -x509 -nodes -newkey rsa:2048 -sha256 -days 1 \
  -keyout "$CERT_DIR/ca.key" \
  -out "$CERT_DIR/ca.pem" \
  -subj "/CN=aarondb-test-ca" \
  -addext "basicConstraints=critical,CA:true" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  >/dev/null 2>&1

make_leaf() {
  name=$1
  openssl req -new -nodes -newkey rsa:2048 -sha256 \
    -keyout "$CERT_DIR/$name.key" \
    -out "$CERT_DIR/$name.csr" \
    -subj "/CN=$HOST_FQDN" \
    >/dev/null 2>&1
  openssl x509 -req -sha256 -days 1 \
    -in "$CERT_DIR/$name.csr" \
    -CA "$CERT_DIR/ca.pem" \
    -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial \
    -out "$CERT_DIR/$name.pem" \
    -extfile "$CERT_DIR/leaf.ext" \
    >/dev/null 2>&1
}

make_leaf cluster_a
make_leaf cluster_b
make_leaf cluster_c

for node in cluster_a cluster_b cluster_c; do
  cat > "$CERT_DIR/$node.config" <<EOF
[{server,[{certfile,"$CERT_DIR/$node.pem"},
          {keyfile,"$CERT_DIR/$node.key"},
          {cacertfile,"$CERT_DIR/ca.pem"},
          {verify,verify_peer},
          {fail_if_no_peer_cert,true}]},
 {client,[{certfile,"$CERT_DIR/$node.pem"},
          {keyfile,"$CERT_DIR/$node.key"},
          {cacertfile,"$CERT_DIR/ca.pem"},
          {verify,verify_peer}]}].
EOF
done

export PATH="/opt/homebrew/bin:$PATH"
cd "$ROOT"
erlc -Werror -o build/dev/erlang/aarondb/ebin src/aarondb_cluster_transport_ffi.erl
erlc -Werror -o build/dev/erlang/aarondb/ebin scripts/aarondb_tls_cluster_runner.erl
RUNTIME_WORKLOAD_OPS=${AARONDB_PERF_WORKLOAD_OPS:-100}
export AARONDB_TLS_WORKLOAD_OPS="$RUNTIME_WORKLOAD_OPS"
RUN_ID=${AARONDB_TLS_RUN_ID:-"$(date +%s)-$$"}
export AARONDB_TLS_RUN_ID="$RUN_ID"
AARONDB_TLS_CERT_DIR="$CERT_DIR" erl -noshell \
  -sname "aarondb_tls_controller_$RUN_ID" \
  -setcookie aarondb_tls_test_cookie \
  -kernel prevent_overlapping_partitions false \
  -proto_dist inet_tls \
  -ssl_dist_optfile "$CERT_DIR/cluster_a.config" \
  -pa build/dev/erlang/aarondb/ebin \
  -eval 'aarondb_tls_cluster_runner:run().' \
  -s init stop
