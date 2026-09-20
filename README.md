# V Rising on GKE

A single, stateful [V Rising](https://playvrising.com/) dedicated server
([`trueosiris/vrising`](https://hub.docker.com/r/trueosiris/vrising)) on **Google Kubernetes
Engine**, provisioned with **Terraform**, deployed by **GitHub Actions**, with a **nightly
scale-down** to cut cost.

## Why GKE (not EKS)

This is one stateful process, not an elastic workload — Kubernetes buys reproducibility and CI/CD
here, not scaling. GCP is materially cheaper for it: a **zonal GKE cluster's control plane is
free**, whereas EKS charges ~$73/mo for the control plane plus a paid UDP NLB. Estimated
**~$70–90/mo** here vs **~$150–200/mo** on EKS — see [Cost](#cost).

## Architecture

```
GCP project
└─ VPC + subnet + firewall (UDP 9876/9877; TCP 25575 RCON optional)
   └─ GKE ZONAL cluster (control plane FREE) + Workload Identity
      └─ node pool "game": 1x e2-standard-4 (amd64/AVX), node_count 0..1
         └─ ns vrising
            └─ StatefulSet vrising (replicas 1)
               ├─ PVC server        (standard-rwo, rebuilt from Steam)
               ├─ PVC persistentdata (vrising-retain, Retain)  ← world saves
               ├─ envFrom ConfigMap (server config) + Secret (passwords)
               └─ Service LoadBalancer (UDP) → reserved static IP  ← stable endpoint
Cloud Scheduler: setSize node pool → 0 at night / 1 in the morning
GitHub Actions: OIDC (WIF) → get-gke-credentials → kubectl apply -k
```

Key constraints baked into the manifests: **x86_64 only** (Wine + AVX), **slow boot** (~10 min
SteamCMD/Wine → long startup probe), **graceful SIGTERM save** (`terminationGracePeriodSeconds:
120`), and a **stable static IP** so nightly node recreation doesn't change the connect address.

## Prerequisites

- A GCP project with billing enabled.
- `gcloud`, `terraform` (>= 1.5), `kubectl` installed. (WSL is fine.)
- A GitHub repo for this code (for CI/CD).

## Setup

### 1. Provision infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit project_id, github_repo, ...
terraform init
terraform apply
```

Note the outputs — you'll need `static_ip`, `workload_identity_provider`, and
`deployer_service_account`.

### 2. Point the LoadBalancer at the static IP

Edit `k8s/overlays/gke/patches/service-ip.yaml` and set `loadBalancerIP` to the `static_ip`
output. Optionally pin the image in `k8s/overlays/gke/kustomization.yaml` (`newTag`) to a dated
tag or digest instead of `latest`.

### 3. Get credentials and create the Secret

```bash
make creds PROJECT=<project> CLUSTER=vrising ZONE=<zone>
kubectl create namespace vrising   # or let `make deploy` create it first
make secret                        # prompts for server + RCON passwords
```

For a public (no-password) server, leave the server password blank.

### 4. Deploy

```bash
make deploy        # kubectl apply -k k8s/overlays/gke
make logs          # watch SteamCMD update → "Starting V Rising Dedicated Server"
make ip            # external IP (should match the reserved static IP)
```

First boot takes a few minutes. Connect from the V Rising client via **direct connect** to
`STATIC_IP:9876`, or find it in the in-game/Steam list (`ListOnSteam`/`ListOnEOS` are on).

### 5. Wire up CI/CD

In the GitHub repo, set:

| Kind | Name | Value (from Terraform) |
|------|------|------------------------|
| Secret | `WIF_PROVIDER` | `workload_identity_provider` |
| Secret | `WIF_SERVICE_ACCOUNT` | `deployer_service_account` |
| Variable | `GKE_CLUSTER` | `vrising` |
| Variable | `GKE_LOCATION` | your zone |

Now a push to `main` touching `k8s/**` runs `.github/workflows/deploy.yml` (keyless — no JSON
key) and rolls out the change.

## Configuration

- **Server settings** — `k8s/base/configmap.yaml`. `HOST_SETTINGS_*` / `GAME_SETTINGS_*` are
  written into the server's JSON on boot (nested keys use `__`). See the
  [docker-vrising README](https://github.com/TrueOsiris/docker-vrising).
- **Passwords / RCON** — the `vrising-secrets` Secret (see `k8s/base/secret.example.yaml`). To use
  RCON, set `HOST_SETTINGS_Rcon__Enabled: "true"`, add the `25575/TCP` port to the StatefulSet and
  Service, and enable + lock down the RCON firewall rule in Terraform.

## Cost

| Item | This stack (GKE) | AWS EKS |
|---|---|---|
| Control plane | **$0** (free zonal cluster) | ~$73/mo |
| Node (4 vCPU/16Gi) | ~$98/mo 24/7 → **~$65/mo** w/ nightly scale-down | ~$70–120/mo |
| UDP load balancer | ~$18/mo | ~$16/mo NLB |
| Disks (~25Gi) + static IP | ~$2–3/mo | ~$6/mo |
| **Total** | **~$70–90/mo** | **~$150–200/mo** |

Further levers: 1-yr Committed Use Discount (~35% off the node), `e2-standard-2` for small
groups, or drop the ~$18 LB with an `external-dns` + Cloud DNS hostname (see below).

The **scale-down** (default 03:00→0 nodes, 16:00→1, `Europe/Paris`) is two Cloud Scheduler jobs
that resize the node pool. While at 0 nodes the pod is `Pending` and no compute is billed; the
world save survives on the retained persistent disk. Tune the crons in `terraform.tfvars`.

## Operations

```bash
make status        # pods / pvcs / service
make logs          # tail the server log
make scale-up      # force node pool → 1 (server up)
make scale-down    # force node pool → 0 (server down, saves cost)
```

The scheduler jobs run automatically; `make scale-up/down` are manual overrides.

## Notes & tradeoffs

- **Stable endpoint requires the LB.** A cheaper `hostPort` exposure loses its IP on nightly node
  recreation. The ~$18/mo LB + reserved IP is the price of a stable connect address under
  scale-down. The true $0-LB path is `hostPort` + `external-dns` + a Cloud DNS zone (stable
  *hostname*, DNS-propagation lag on each scale-up) — not wired up here by default.
- **Image is consumed, not built.** We pull the public upstream image. If you fork and modify the
  `Dockerfile`, add a build workflow that pushes to *your* Docker Hub repo (needs
  `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` secrets) and point the overlay `newTag` at it.
- **Terraform apply is manual/gated** (run locally); only app deploys are automated in CI.
```
