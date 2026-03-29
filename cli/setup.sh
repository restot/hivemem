# =========================================================================
# trust_server_cert — Fetch and trust the server's CA certificate
# =========================================================================
trust_server_cert() {
  local hostport="${1:?Usage: trust_server_cert host:port}"
  local cert_dir="$HOME/.hivemem"
  local ca_file="$cert_dir/ca.pem"

  need openssl

  mkdir -p "$cert_dir"

  info "TLS certificate setup"

  if curl -s --connect-timeout 3 "https://$hostport/health" >/dev/null 2>&1; then
    skip "TLS already trusted for $hostport"
    return 0
  fi

  local cert_chain
  cert_chain="$(openssl s_client -connect "$hostport" -servername "${hostport%%:*}" \
    -showcerts </dev/null 2>/dev/null \
    | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{print}' \
    | awk 'BEGIN{cert=""} /BEGIN CERTIFICATE/{cert=""} {cert=cert $0 "\n"} /END CERTIFICATE/{last=cert} END{printf "%s", last}' \
    || true)"

  if [[ -z "$cert_chain" ]]; then
    warn "Could not fetch certificate from $hostport"
    return 1
  fi

  echo "$cert_chain" > "$ca_file"
  ok "CA cert saved -> $ca_file"

  if [[ "$(uname)" == "Darwin" ]]; then
    info "Trusting CA cert on macOS (requires sudo)"
    if sudo security add-trusted-cert -d -r trustRoot \
      -k /Library/Keychains/System.keychain "$ca_file" 2>/dev/null; then
      ok "CA cert trusted in system keychain"
    else
      warn "Could not add to system keychain. You may need to trust manually."
    fi
  fi
}

# =========================================================================
# setup — Bootstrap the hivemem server
# =========================================================================
cmd_setup() {
  local extra_hostname=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hostname) extra_hostname="$2"; shift 2 ;;
      *) die "setup: unknown option $1" ;;
    esac
  done

  need openssl
  need python3

  local project_root
  project_root="$(find_project_root)"
  local certs_dir="$project_root/certs"
  local env_file="$project_root/.env"
  local env_example="$project_root/.env.example"

  # --- 1. TLS certs ---
  info "TLS certificates"
  mkdir -p "$certs_dir"

  if [[ -f "$certs_dir/hivemem-ca.pem" && -f "$certs_dir/server.pem" ]]; then
    skip "Certs in $certs_dir"
  else
    local san="DNS:localhost,IP:127.0.0.1"
    [[ -n "$extra_hostname" ]] && san="$san,DNS:$extra_hostname"

    openssl genrsa -out "$certs_dir/hivemem-ca-key.pem" 4096 2>/dev/null
    openssl req -new -x509 -key "$certs_dir/hivemem-ca-key.pem" \
      -sha256 -days 3650 \
      -subj "/CN=hivemem-ca/O=hivemem-dev" \
      -out "$certs_dir/hivemem-ca.pem" 2>/dev/null
    ok "CA cert -> certs/hivemem-ca.pem"

    openssl genrsa -out "$certs_dir/server-key.pem" 2048 2>/dev/null
    openssl req -new -key "$certs_dir/server-key.pem" \
      -subj "/CN=localhost/O=hivemem-dev" \
      -out "$certs_dir/server.csr" 2>/dev/null
    openssl x509 -req -in "$certs_dir/server.csr" \
      -CA "$certs_dir/hivemem-ca.pem" \
      -CAkey "$certs_dir/hivemem-ca-key.pem" \
      -CAcreateserial -sha256 -days 825 \
      -extfile <(printf "subjectAltName=%s\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth" "$san") \
      -out "$certs_dir/server.pem" 2>/dev/null
    ok "Server cert -> certs/server.pem (SAN: $san)"

    rm -f "$certs_dir/server.csr" "$certs_dir/hivemem-ca.srl"
  fi

  # --- 2. Auth token ---
  info "Auth token"
  local token
  token="$(openssl rand -hex 32)"

  if [[ ! -f "$env_file" ]]; then
    if [[ -f "$env_example" ]]; then
      cp "$env_example" "$env_file"
      ok "Created .env from .env.example"
    else
      touch "$env_file"
      ok "Created empty .env"
    fi
  fi

  local existing_token
  existing_token="$(grep -E '^HIVEMEM_AUTH_TOKEN=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"

  if [[ -n "$existing_token" ]]; then
    token="$existing_token"
    skip "HIVEMEM_AUTH_TOKEN already set"
  else
    if grep -qE '^HIVEMEM_AUTH_TOKEN=' "$env_file" 2>/dev/null; then
      if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s|^HIVEMEM_AUTH_TOKEN=.*|HIVEMEM_AUTH_TOKEN=$token|" "$env_file"
      else
        sed -i "s|^HIVEMEM_AUTH_TOKEN=.*|HIVEMEM_AUTH_TOKEN=$token|" "$env_file"
      fi
    else
      echo "HIVEMEM_AUTH_TOKEN=$token" >> "$env_file"
    fi
    ok "HIVEMEM_AUTH_TOKEN written to .env"
  fi

  # --- 3. Global config ---
  info "Hivemem config"
  local config_dir="$HOME/.hivemem"
  mkdir -p "$config_dir"

  local config_content
  config_content="$(printf 'server_url=%s\nauth_token=%s\n' "$DEFAULT_SERVER_URL" "$token")"
  if [[ -f "$config_dir/config" ]] && [[ "$(cat "$config_dir/config")" == "$config_content" ]]; then
    skip "Config unchanged"
  else
    printf '%s\n' "$config_content" > "$config_dir/config"
    ok "Config -> $config_dir/config"
  fi

  # --- 4. Trust CA cert ---
  if [[ -f "$certs_dir/hivemem-ca.pem" ]]; then
    cp "$certs_dir/hivemem-ca.pem" "$config_dir/ca.pem"
    ok "CA cert -> $config_dir/ca.pem"

    if [[ "$(uname)" == "Darwin" ]]; then
      info "Trusting CA cert on macOS (requires sudo)"
      if sudo security add-trusted-cert -d -r trustRoot \
        -k /Library/Keychains/System.keychain "$config_dir/ca.pem" 2>/dev/null; then
        ok "CA cert trusted in system keychain"
      else
        warn "Could not add to system keychain"
      fi
    fi
  fi

  echo ""
  info "Setup complete"
  echo ""
  echo "  Server URL:  $DEFAULT_SERVER_URL"
  echo "  TLS certs:   $certs_dir/"
  echo "  CA cert:     $config_dir/ca.pem (trusted)"
  echo "  Auth token:  .env (HIVEMEM_AUTH_TOKEN)"
  echo "  Config:      $config_dir/config"
  echo ""
  echo "  Next steps:"
  echo "    cd $project_root && docker compose up -d"
  echo "    hivemem init    # in your project directory"
  echo ""
}
