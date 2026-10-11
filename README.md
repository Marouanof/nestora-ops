# nestora-ops — production deployment of Nestora (lite)

DevOps delivery layer for [Nestora](https://github.com/Marouanof/Nestora), scoped to the **lite** slice:
`postgres + user-service + gateway + frontend`. Remaining microservices (property/booking/payment/notification)
keep `*_SERVICE_URI`-style routing toward `user-service` until containerized (see Roadmap).

```
Browser -> frontend (Nginx :80, /api -> gateway) -> gateway :8080 -> user-service :8081 -> postgres :5432
CI: GitHub Actions (test -> build -> Trivy scan -> push to GHCR)
Infra: Terraform on OCI Always Free (VCN + Ampere VM + k3s via cloud-init)
K8s: plain manifests + Kustomize (namespace nestora) | Obs: Prometheus + Grafana + postgres-exporter + blackbox
Object storage: local volume (dev) / S3Mock (S3 API testing) / AWS S3 (prod) — see §7
```

[![CI](https://github.com/Marouanof/nestora-ops/actions/workflows/ci.yml/badge.svg)](https://github.com/Marouanof/nestora-ops/actions/workflows/ci.yml)

## 1. Local run (~15 min)

```powershell
# 0. Prereqs: Docker Desktop running
# 1. Sync nginx config into the Nestora frontend checkout
.\scripts\sync-dockerfiles.ps1
# 2. Local secrets
copy .env.example .env
#    -> fill POSTGRES_PASSWORD, JWT_SECRET (>= 32 chars), GATEWAY_SHARED_SECRET
#    (generate with: openssl rand -base64 48)
# 3. Build + run
docker compose --env-file .env up --build -d
docker compose ps
curl http://localhost:8080/actuator/health   # gateway
curl http://localhost:8081/actuator/health   # user-service
# front: http://localhost/
# 4. Logs
docker compose logs -f gateway user-service
# 5. Stop
docker compose down        # add -v to wipe postgres
```

Monitoring overlay: `docker compose -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml up -d`
-> Prometheus http://localhost:9091, Grafana http://localhost:3000 (admin / `$GRAFANA_PASSWORD`).

## 2. CI (GitHub Actions)

Workflow `.github/workflows/ci.yml`: dual checkout (ops + Nestora), Maven tests (`user-service`, `gateway`),
Vite lint + build, Docker build/push to GHCR (`nestora-user-service`, `nestora-gateway`, `nestora-frontend`,
tags `:latest` + `:<sha>`), Trivy HIGH/CRITICAL scan (SARIF, non-blocking).

No extra secrets required for GHCR on public repos (`GITHUB_TOKEN` is enough).

## 3. Kubernetes

```bash
cp k8s/base/secret.example.yaml k8s/base/secret.yaml  # fill in, file is gitignored
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/secret.yaml
kubectl apply -k k8s/base   # or: kubectl apply -f k8s/base/*.yaml
kubectl -n nestora get pods,svc
kubectl -n nestora port-forward svc/frontend 8088:80   # local front without ingress
```

Default images: `ghcr.io/marouanof/nestora-*`. Replace `marouanof` with your GHCR owner on fork.
Ingress included for clusters with ingress-nginx; on the OCI VM, NodePort 30080 is opened in the security list.

## 4. OCI infrastructure (Terraform, Always Free)

```bash
cd terraform/oci
cp terraform.tfvars.example terraform.tfvars   # fill in OCIDs + API key + SSH key
terraform init && terraform fmt -check && terraform validate
terraform plan -out plan.out
terraform apply plan.out
# -> outputs: k3s_public_ip, ssh_cmd, kubeconfig_cmd
ssh opc@<ip> "cat /root/k3s-ready.txt"
scp opc@<ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/nestora-oci.yaml
# set server: https://<ip>:6443, then:
kubectl --kubeconfig ~/.kube/nestora-oci.yaml -n nestora get nodes
```

Defaults (2 OCPU / 12 GB) fit the Ampere Always Free quota (4 OCPU / 24 GB). `terraform destroy` releases everything.

## 5. Architecture decisions

- Multi-stage Docker builds: runtime images ship no JDK/Maven/Node (~-70% size), non-root user, HEALTHCHECK.
- `SPRING_PROFILES_ACTIVE=prod`: all config comes from env vars (`application-prod.properties` / `application.yml`), nothing hardcoded.
- Gateway: centralized routing + JWT + CORS; frontend calls relative `/api`, proxied by Nginx (no CORS in prod).
- CI: test first, immutable `:<sha>` tag + `:latest`, Trivy scan before push.
- K8s: one shared Secret, `/actuator/health` probes, requests/limits sized for a small VM, 5 GB PVC.
- Terraform: deny-by-default network, only 22/80/443/30080 open, idempotent cloud-init, local state (Object Storage backend as next step).

## 6. Skills demonstrated

Docker · GitHub Actions · Kubernetes · Terraform · OCI · Prometheus/Grafana · GHCR · Trivy · S3-compatible storage

## 7. Object storage: local / S3Mock / AWS

`user-service` selects storage via `STORAGE_TYPE` (`storage.type`):

| Mode | Use | Config |
|---|---|---|
| `local` (default) | dev, tests, CI | `FILE_UPLOAD_DIR=/app/uploads` (created in the image, non-root owned) |
| `s3` + S3Mock | S3 API testing, no AWS account | uncomment the S3 block in `docker-compose.yml`: endpoint `http://s3mock:9090`, bucket auto-created at startup (`INITIAL_BUCKETS`), verify with `curl http://localhost:9090/<bucket>/` |
| `s3` + AWS | prod | same variables, empty endpoint (= real AWS) + real keys + existing AWS bucket |

Notes:
- S3Mock (Adobe, `adobe/s3mock`, 81 MB) is **path-style only** (`host/bucket/key`): hence `forcePathStyle(true)` in `S3Config` whenever an endpoint is set — required, not optional.
- `S3Config`: empty `aws.s3.endpoint` = real AWS; set = S3-compatible endpoint.
- `S3FileStorageService`: returned URLs follow the endpoint (`http://s3mock:9090/bucket/key` locally, `bucket.s3.region.amazonaws.com` format on AWS).
- Buckets private by default (fits KYC documents); relax explicitly if avatars must be public.

## 8. Roadmap

1. `micrometer-registry-prometheus` in the poms -> scrape `/actuator/prometheus` instead of blackbox-only.
2. Containerize property/booking/notification + RabbitMQ, real gateway URIs.
3. GitOps CD with ArgoCD + 2 envs (staging/prod) via Kustomize overlays.
4. Terraform remote state (OCI Object Storage) + Vault/External Secrets.
