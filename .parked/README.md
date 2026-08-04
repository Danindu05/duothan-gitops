# Parked

Written, reviewed, and not currently applied. They are kept here rather than
deleted because the work is sound and the obstacles are specific and named.

## `admission.yaml` + `admission-policies/` — Kyverno image verification

The policies are complete: keyless signature verification against this project's
build workflow, with verified images rewritten to the digest that was checked, and
a second policy refusing `latest`.

**Blocked on:** the Kyverno chart failing to render on this cluster
(`coalesce.go` error during `helm template`). The failure is in the chart's own
value merging, not in the policies. Installing Kyverno by hand and applying
`admission-policies/` directly would work; doing it through this chart needs the
values narrowed down further.

**Also needed first:** every running image must come from GHCR and be signed.
Turning enforcement on while services still run Docker Hub images would refuse
nothing — the rule only matches `ghcr.io/danindu05/aegis-*` — so it would give the
appearance of protection without the fact of it.

## `runtime-security.yaml` — Falco

The rules are written for these images in particular: they ship no shell anyone
should be using and no network tooling, so either appearing is worth an alert.

**Blocked on:** the driver failing to start — `Initialization issues during
scap_init`. Raising `fs.inotify.max_user_instances` from 128 to 1024 on the node
got it past its first failure, and it now fails later, in the eBPF probe. This is
a kernel-and-privileges question on this particular VM rather than a
misconfiguration of the rules.

**Worth trying next:** the `ebpf` driver rather than `modern_ebpf`, or granting
the probe `CAP_BPF`, `CAP_PERFMON` and `CAP_SYS_RESOURCE` explicitly.
