#!/usr/bin/env bash
# Initialises and unseals Vault inside the cluster, then issues the AppRole the
# services authenticate with.
#
# The root key is split with Shamir's Secret Sharing — five shares, any three to
# unseal — the same custodian model the platform applies to its own Master Key.
# Shares are written to ./vault-keys.json on the machine running this script and
# must be distributed and removed; they are the keys to the kingdom.
set -euo pipefail

NAMESPACE=aegis
POD=$(kubectl get pod -n "$NAMESPACE" -l app=vault -o jsonpath='{.items[0].metadata.name}')
exec_vault() { kubectl exec -n "$NAMESPACE" "$POD" -- env VAULT_ADDR=http://127.0.0.1:8200 "$@"; }

echo "Waiting for Vault to listen…"
until exec_vault vault status >/dev/null 2>&1 || [ $? -eq 2 ]; do sleep 2; done

if [ "$(exec_vault vault status -format=json | jq -r .initialized)" != "true" ]; then
    echo "Initialising Vault (Shamir 3-of-5)…"
    exec_vault vault operator init -key-shares=5 -key-threshold=3 -format=json > vault-keys.json
    chmod 600 vault-keys.json
fi

if [ "$(exec_vault vault status -format=json | jq -r .sealed)" = "true" ]; then
    echo "Unsealing with 3 of 5 shares…"
    for i in 0 1 2; do
        exec_vault vault operator unseal "$(jq -r ".unseal_keys_b64[$i]" vault-keys.json)" >/dev/null
    done
fi

TOKEN=$(jq -r .root_token vault-keys.json)
run() { kubectl exec -n "$NAMESPACE" "$POD" -- env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$TOKEN" "$@"; }

run vault secrets enable -path=secret kv-v2 >/dev/null 2>&1 || true
run vault auth enable approle >/dev/null 2>&1 || true

kubectl exec -i -n "$NAMESPACE" "$POD" -- env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$TOKEN" \
    vault policy write aegis-platform - <<'POLICY' >/dev/null
path "secret/data/aegis/*"     { capabilities = ["create", "read", "update"] }
path "secret/metadata/aegis/*" { capabilities = ["read", "list"] }
POLICY

run vault write auth/approle/role/aegis-platform \
    token_policies=aegis-platform token_ttl=1h token_max_ttl=4h secret_id_num_uses=0 >/dev/null

ROLE_ID=$(run vault read -field=role_id auth/approle/role/aegis-platform/role-id)
SECRET_ID=$(run vault write -f -field=secret_id auth/approle/role/aegis-platform/secret-id)

kubectl create secret generic aegis-vault-approle -n "$NAMESPACE" \
    --from-literal=role_id="$ROLE_ID" \
    --from-literal=secret_id="$SECRET_ID" \
    --dry-run=client -o yaml | kubectl apply -f -

echo
echo "Vault unsealed and AppRole issued."
echo "IMPORTANT: vault-keys.json holds all five unseal shares — distribute them to"
echo "custodians and delete this file. Without them the vault cannot be reopened."
