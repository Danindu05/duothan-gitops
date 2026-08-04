# Environments

The chart in `../charts/aegis-service` describes what an AEGIS service *is*: a
progressive-delivery rollout, the two services that route to it, and the gate that
decides whether a release continues. It knows nothing about where it runs.

```
charts/aegis-service/          what a service is       (Helm — packaged, reusable)
environments/base/*.yaml       what each service is    (name, database, strategy)
environments/production/       what is true here       (registry, replicas)
```

`base/` holds one file per service, and each states only what differs — usually a
name, a database and a delivery strategy. The nine hand-written rollouts these
replace came to 902 lines, and any two of them differed by roughly eight. That
ratio is not redundancy; it is nine chances to fix something in eight places.

`production/` carries the environment's own decisions. It is deliberately thin: an
overlay that restates the service is not an overlay, and it puts back exactly the
duplication the chart removed.

Adding an environment means one more directory here, not another copy of nine
manifests.
