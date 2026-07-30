#!/usr/bin/env bash
# Creates the secrets the platform needs. Deliberately NOT in Git: connection
# strings and Vault credentials never belong in a repository, even a private one.
#
#   ./scripts/create-secrets.sh
#
# Reads the same .env the compose stack uses, so there is one place to change a
# password rather than two.
set -euo pipefail

ENV_FILE="${1:-$HOME/duothan-app/.env}"
[ -f "$ENV_FILE" ] || { echo "No .env at $ENV_FILE — pass the path as the first argument."; exit 1; }

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

kubectl create namespace aegis --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic aegis-databases -n aegis \
  --from-literal=identity="${IDENTITY_DB:?IDENTITY_DB missing}" \
  --from-literal=account="${ACCOUNT_DB:?ACCOUNT_DB missing}" \
  --from-literal=transaction="${TRANSACTION_DB:?TRANSACTION_DB missing}" \
  --from-literal=payment="${PAYMENT_DB:?PAYMENT_DB missing}" \
  --from-literal=lending="${LENDING_DB:?LENDING_DB missing}" \
  --from-literal=platform="${PLATFORM_DB:?PLATFORM_DB missing}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Database secrets applied."
echo "Vault AppRole credentials are issued by scripts/bootstrap-vault.sh once Vault is running."
