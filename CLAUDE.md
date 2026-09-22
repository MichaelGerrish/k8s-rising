# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Infrastructure-as-code for a single stateful [V Rising](https://playvrising.com/) dedicated
server (upstream image `trueosiris/vrising`) on **Google Kubernetes Engine**: **Terraform** for
GCP infra, **Kustomize** manifests for the workload, **GitHub Actions** for app deploys, and
**Cloud Scheduler** for a nightly node-pool scale-down. There is no application code to build or
test here — the container image is consumed from upstream, not built.

`docker-vrising/` is an embedded clone of the upstream image source
(`github.com/TrueOsiris/docker-vrising`), tracked by the parent repo as a bare gitlink (not a
configured submodule — there is no `.gitmodules`). Treat it as vendored reference, not code to
edit or commit: the manifests here depend on how its `start.sh` behaves (traps SIGTERM to flush
the save, checks for AVX, applies a CRLF fix), so read it to understand the workload, but changes
belong upstream.

## Commands

Everything routes through the `Makefile` (thin wrappers over `terraform`, `gcloud`, `kubectl`).
Override defaults on the command line, e.g. `make creds PROJECT=my-proj ZONE=us-central1-a`.
Defaults: `CLUSTER=vrising`, `ZONE=us-west4-a`, `POOL=game`, `NS=vrising`.

```bash
make tf-init / tf-plan / tf-apply / tf-destroy   # Terraform (run locally; tf-destroy keeps the world-save disk)
make creds PROJECT=<id> ZONE=<zone>              # fetch kubectl credentials
make secret                                      # create vrising-secrets interactively (server + RCON passwords)
make deploy                                      # kubectl apply -k k8s/overlays/gke
make status / logs / ip                          # pods+pvc+svc / tail server log / external LB IP
make scale-up / scale-down                       # manual node-pool resize (override the scheduler)
```

There is no lint or test target. Validate changes with `terraform plan`, `terraform validate`,
and `kubectl apply -k k8s/overlays/gke --dry-run=client` / `kubectl kustomize k8s/overlays/gke`.

## Architecture and the constraints that shaped it

The **intended** CI flow: a push to `main` touching `k8s/**` triggers `.github/workflows/deploy.yml`,
which authenticates to GCP **keylessly** via Workload Identity Federation (no JSON key), fetches
GKE credentials, runs `kubectl apply -k k8s/overlays/gke`, and waits for the StatefulSet rollout.
**Terraform apply is never automated** — it is run manually/locally; only app manifest deploys go
through CI.

**Caveat: the workflow file is not committed yet.** There is currently no `.github/` directory at
the repo root — `deploy.yml` is described here and in the README but does not exist in the tree.
Until it is added, deploys happen only via `make deploy` locally. The Terraform WIF wiring
(`terraform/github_oidc.tf`) that the workflow would consume *is* in place. If you are asked to
"fix the deploy" or wire up CI, the first step is authoring this workflow, not debugging an
existing one.

**Deliberate design decisions, each load-bearing:**

- **Zonal (not regional) GKE cluster** (`terraform/gke.tf`, `location = var.zone`) — a zonal
  cluster's control plane is on GKE's free tier; a regional one costs ~$73/mo. This is the whole
  cost argument for GKE over EKS. Do not change the cluster to regional casually.
- **Node pool managed by Cloud Scheduler, not the autoscaler** — `terraform/scheduler.tf` creates
  two Cloud Scheduler jobs that hit the node pool's `:setSize` API to go to 0 nodes at night and 1
  in the morning. Because the scheduler changes `node_count` out of band, the node pool has
  `lifecycle { ignore_changes = [node_count] }` so Terraform won't fight it. At 0 nodes the pod is
  `Pending`, no compute is billed, and the world save survives on the retained disk.
- **Reserved static IP + UDP LoadBalancer** (`terraform/network.tf`, `google_compute_address`;
  overlay patch `k8s/overlays/gke/patches/service-ip.yaml` sets `loadBalancerIP`) — nightly node
  recreation would otherwise change the connect address. The stable player-facing endpoint is the
  reason the ~$18/mo LB is accepted rather than cheaper `hostPort`.
- **x86_64 only** — the server is a Windows binary run under Wine and `start.sh` checks for AVX,
  so the StatefulSet pins `nodeSelector: kubernetes.io/arch: amd64`. Keep the machine type in the
  `e2-standard-*` (Intel/amd64) family; never move this to arm nodes.
- **Slow boot + graceful save** — SteamCMD update + Wine startup takes ~5–10 min, so the
  `startupProbe` has a ~12 min budget (`failureThreshold: 24 × periodSeconds: 30`). `start.sh`
  traps SIGTERM to flush the save, so `terminationGracePeriodSeconds: 120`. Probes exec
  `pgrep -f VRisingServer.exe` because the server exposes no HTTP endpoint.
- **Two persistent volumes with opposite reclaim policies** (`volumeClaimTemplates`) — `server`
  uses `standard-rwo` (rebuilt from Steam, safe to Delete); `persistentdata` uses the custom
  `vrising-retain` StorageClass (world saves, **Retain** on teardown). `tf-destroy` and PVC
  deletion preserve the save because of this split.

## Kustomize layout

- `k8s/base/` — namespace, custom `vrising-retain` StorageClass, ConfigMap, UDP Service,
  StatefulSet. The Secret is **intentionally excluded** from `kustomization.yaml`; create the real
  `vrising-secrets` out of band with `make secret` (`secret.example.yaml` is a template only).
- `k8s/overlays/gke/` — patches the Service with the reserved static IP and pins the image tag.
  The base uses `image: trueosiris/vrising:latest`; the overlay's `images[].newTag` should be set
  to a dated tag or digest for reproducible deploys.

## Configuration surfaces

- **Server settings** — `k8s/base/configmap.yaml`. `HOST_SETTINGS_*` / `GAME_SETTINGS_*` env vars
  are written into the server's JSON on boot; nested JSON keys are expressed with `__`.
- **Secrets** — `vrising-secrets` (server password, RCON password). Leaving the server password
  unset yields a public server.
- **RCON is off by default and requires three coordinated changes**: set
  `HOST_SETTINGS_Rcon__Enabled: "true"` in the ConfigMap, add the `25575/TCP` port to both the
  StatefulSet and the Service, and enable + lock down `google_compute_firewall.vrising_rcon` in
  `terraform/network.tf` (its `source_ranges` currently `0.0.0.0/0` — tighten to your /32).

## Wiring Terraform outputs to GitHub

After `terraform apply`, set in the GitHub repo: secrets `WIF_PROVIDER`
(`workload_identity_provider` output) and `WIF_SERVICE_ACCOUNT` (`deployer_service_account`), and
variables `GKE_CLUSTER` and `GKE_LOCATION` (the zone). The WIF provider only accepts tokens from
the repo named in `var.github_repo` (`terraform/github_oidc.tf`).
