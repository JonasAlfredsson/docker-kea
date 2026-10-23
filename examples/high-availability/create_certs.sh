#!/bin/bash
# Create a local CA and certificates for mutual TLS between the HA peers.
# Each peer acts as both a TLS client and server, so its certificate permits both.
#
# Run on the host from this example directory before starting Docker Compose:
#   sudo ./create_certs.sh
# Requires OpenSSL and root to assign peer credentials to UID:GID 101:101 (kea).
# Output is always tls/ beside this script; existing output paths are refused.
# Keep the CA private key on the host; containers need only their own credentials
# and the public CA certificate. Private keys are unencrypted with mode 0600.
# Peer certificates expire after 365 days; renewal is not automated.
# This secures HA traffic, not the separate HTTP management API.

set -euo pipefail
umask 077

if (( EUID != 0 )); then
    printf 'Run this script as root to set certificate ownership to 101:101.\n' >&2
    exit 1
fi

# Do not overwrite an already existing TLS directory.
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tls_dir="${script_dir}/tls"

if [[ -e "$tls_dir" || -L "$tls_dir" ]]; then
    printf 'Refusing to overwrite existing TLS directory: %s\n' "$tls_dir" >&2
    exit 1
fi


# Prepare the workspace and expected directories.
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT
mkdir -- "$tls_dir"
mkdir -- "$tls_dir/dhcp-1" "$tls_dir/dhcp-2"



# Create a configuration file for generating a properly configured CA certificate.
cat > "$work_dir/ca.cnf" <<'EOF'
[req]
prompt = no
distinguished_name = ca_name
x509_extensions = ca_cert

[ca_name]
CN = Kea HA Example CA

[ca_cert]
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

# Generate a CA key/certificate pair using the configuration file.
openssl req -new -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
    -config "$work_dir/ca.cnf" \
    -keyout "$tls_dir/ca.key" -out "$tls_dir/ca.crt"


# Generate peer certificates for each HA peer.
for peer in dhcp-1 dhcp-2; do
    if [[ "$peer" == dhcp-1 ]]; then
        peer_ip=10.10.10.2
    else
        peer_ip=10.10.10.3
    fi

    cat > "$work_dir/peer.cnf" <<EOF
[peer_cert]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:${peer}, IP:${peer_ip}
EOF

    # Generate a certificate signing request (CSR) for the peer and sign it with
    # the CA.
    openssl req -new -newkey rsa:3072 -nodes -sha256 \
        -config "$work_dir/ca.cnf" -subj "/CN=${peer}" \
        -keyout "$tls_dir/$peer/private.key" -out "$work_dir/peer.csr"
    serial=$(openssl rand -hex 16)
    openssl x509 -req -sha256 -days 365 -set_serial "0x${serial}" \
        -in "$work_dir/peer.csr" \
        -CA "$tls_dir/ca.crt" -CAkey "$tls_dir/ca.key" \
        -extfile "$work_dir/peer.cnf" -extensions peer_cert \
        -out "$tls_dir/$peer/certificate.crt"

    # Verify the generated certificate against the CA for both server and client purposes.
    openssl verify -x509_strict -purpose sslserver -verify_ip "$peer_ip" \
        -CAfile "$tls_dir/ca.crt" "$tls_dir/$peer/certificate.crt"
    openssl verify -x509_strict -purpose sslclient \
        -CAfile "$tls_dir/ca.crt" "$tls_dir/$peer/certificate.crt"

    # Set appropriate ownership and permissions for the peer's TLS directory and files.
    chown 101:101 "$tls_dir/$peer" "$tls_dir/$peer/private.key" "$tls_dir/$peer/certificate.crt"
    chmod 0755 "$tls_dir/$peer"
    chmod 0600 "$tls_dir/$peer/private.key"
    chmod 0644 "$tls_dir/$peer/certificate.crt"
done

# Set appropriate permissions for the CA directory and files.
chown 0:0 "$tls_dir" "$tls_dir/ca.key" "$tls_dir/ca.crt"
chmod 0755 "$tls_dir"
chmod 0600 "$tls_dir/ca.key"
chmod 0644 "$tls_dir/ca.crt"

printf 'Created CA and peer credentials in %s\n' "$tls_dir"
