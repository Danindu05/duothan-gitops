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

## Progressive delivery

Nothing is released by replacing what is running. Two strategies are used, split the
way blueprint 7.5 asks for.

**Canary — the seven backend services.** A new version takes half the traffic while
the stable one keeps serving the rest, and only continues if it proves healthy under
that load. A release that misbehaves is seen by a fraction of customers for one
analysis window instead of by everyone at once. Weight is approximated by pod count
because there is no service mesh here, so with two replicas the real steps are half
and all; the pauses are what make it a canary rather than a rolling update, since each
one is a point where analysis can stop the release.

**Blue-green — the gateway and the frontend.** The two entry points come up complete
beside the running version and are exercised on their preview host before any traffic
moves. These are the components where a half-migrated state is most visible to a
customer, so they change over all at once or not at all.

| | |
|---|---|
| **gate** | five health checks, ten seconds apart, against the new revision |
| **on failure** | the rollout aborts and traffic stays on the stable version |
| **rollback** | instant — the previous revision is still running |

```bash
kubectl argo rollouts get rollout identity -n aegis --watch   # follow a release
kubectl argo rollouts promote identity -n aegis               # skip a pause
kubectl argo rollouts abort identity -n aegis                 # stop and hold on stable
kubectl argo rollouts undo identity -n aegis                  # go back a revision
```

## How a change reaches the cluster

Nobody applies anything by hand, and no image tag moves.

```
push to duothan-6.0
      ↓  Build and publish images
image pushed as aegis-<service>:sha-<commit>
      ↓  Promote to GitOps
this repository's manifests updated to that tag
      ↓  Argo CD notices the diff
canary or blue-green rollout, gated on analysis
```

The tag names a commit, which is what makes the running system answerable to a line
of history. `latest` cannot be deployed by Argo CD, because it cannot tell one
`latest` from another, and cannot be rolled back to, because yesterday's no longer
exists anywhere.

Promotion needs a `GITOPS_TOKEN` secret on the application repository — a
fine-grained token with Contents: read/write here. The built-in `GITHUB_TOKEN` cannot
reach across repositories.

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
