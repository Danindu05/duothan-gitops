# AEGIS — GitOps

**Duothan 6.0 · Team ScryBug**

Declarative deployment for the AEGIS banking platform. Git is the single source of
truth: Argo CD continuously compares the cluster with this repository and applies
only what is committed here, so every change is reviewable, traceable and
reversible (blueprint §7.4.1).

Application source lives in [`duothan-6.0`](https://github.com/Danindu05/duothan-6.0);
this repository holds only what runs where.

## Layout

```
bootstrap/root-app.yaml     the one Application applied by hand; everything else follows
apps/                       an Argo CD Application per component, ordered by sync wave
manifests/
  namespace.yaml            namespace with Pod Security Standards
  analysis-template.yaml    the health gate a new colour must pass before promotion
  ingress.yaml              Traefik routes for the live and preview colours
  infrastructure/           Vault, RabbitMQ, Redis
  services/                 one blue-green Rollout per service
scripts/                    secret creation and Vault bootstrap (never committed)
```

## Blue-green deployment

Every service is an Argo Rollouts `Rollout`, not a plain `Deployment`. A release
brings up the new colour beside the running one:

| | |
|---|---|
| **active service** | `identity` — carries live customer traffic |
| **preview service** | `identity-preview` — the new colour, reachable but not live |
| **promotion** | manual (`autoPromotionEnabled: false`) |
| **gate** | five consecutive health checks against the preview colour |
| **rollback** | instant — the old colour is still running for 60 seconds |

Nothing reaches customers until a human promotes it:

```bash
kubectl argo rollouts get rollout identity -n aegis --watch   # watch both colours
kubectl argo rollouts promote identity -n aegis               # send traffic to green
kubectl argo rollouts undo identity -n aegis                  # fall back to blue
```

This is what makes a bad release survivable: the previous version never stopped
running, so recovery is a traffic switch rather than a redeploy.

## Sync waves

Components come up in dependency order, so a service never starts against
infrastructure that is not ready:

| Wave | Component |
|---|---|
| 0 | namespace, analysis template, ingress |
| 1 | Vault, RabbitMQ, Redis |
| 2 | platform, identity, account, fraud |
| 3 | transaction, payment, lending |
| 4 | gateway |
| 5 | frontend |

## First install

On the cluster host:

```bash
# 1. Secrets — database connection strings, read from the app repo's .env
./scripts/create-secrets.sh ~/duothan-app/.env

# 2. Tell Argo CD about this repository
kubectl apply -f bootstrap/root-app.yaml

# 3. Once Vault's pod is running, initialise it and issue the services' AppRole
./scripts/bootstrap-vault.sh
```

Argo CD takes it from there: it reads `apps/`, creates one Application per
component, and reconciles them in wave order.

## Secrets

No secret is committed to this repository. Database credentials and the Vault
AppRole are created directly on the cluster by the scripts above, and
`vault-keys.json` — which holds all five unseal shares — is gitignored and must be
distributed to custodians and then deleted. Losing those shares means the vault
cannot be reopened, and with it the encrypted authenticator seeds and card
numbers.

## Access

| | |
|---|---|
| Application | `http://<vm-ip>/` |
| Preview colour | `http://preview.aegis.local/` (point it at the VM in `/etc/hosts`) |
| Argo CD | `kubectl port-forward svc/argocd-server -n argocd 8081:443` |
| Rollouts dashboard | `kubectl argo rollouts dashboard -n aegis` |

Argo CD's initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```
