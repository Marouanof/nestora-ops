# nestora-ops — mise en prod de Nestora (lite)

Industrialisation DevOps de [Nestora](https://github.com/Marouanof/Nestora) en version **lite** :
`postgres + user-service + gateway + frontend`. Les autres microservices (property/booking/payment/notification)
gardent `USER_SERVICE_URI`-style et pointent vers `user-service` en attendant leur conteneurisation (roadmap).

```
Navigateur -> frontend (Nginx :80, /api -> gateway) -> gateway :8080 -> user-service :8081 -> postgres :5432
CI : GitHub Actions (test -> build -> Trivy -> push GHCR)
Infra : Terraform OCI Always Free (VCN + VM Ampere + k3s via cloud-init)
K8s : manifests plain + Kustomize (namespace nestora) | Obs : Prometheus + Grafana + postgres-exporter + blackbox
```

## 1. Démarrage local (Windows, ~15 min)

```powershell
# 0. Préreq : Docker Desktop démarré, WSL2 OK
# 1. Cloner Nestora en frère de ce repo + sync nginx
.\scripts\sync-dockerfiles.ps1
# 2. Secrets locaux
copy .env.example .env
#    -> remplis POSTGRES_PASSWORD, JWT_SECRET (>=32 chars), GATEWAY_SHARED_SECRET
#    (génère avec : openssl rand -base64 48)
# 3. Build + run
docker compose --env-file .env up --build -d
docker compose ps
curl http://localhost:8080/actuator/health   # gateway
curl http://localhost:8081/actuator/health   # user-service
# front : http://localhost/
# 4. Logs
docker compose logs -f gateway user-service
# 5. Stop
docker compose down        # + -v pour purger postgres
```

Option monitoring : `docker compose -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml up -d`
-> Prometheus http://localhost:9090, Grafana http://localhost:3000 (admin / $GRAFANA_PASSWORD).

## 2. CI (GitHub Actions)

Workflow `.github/workflows/ci.yml` : checkout double (ops + Nestora), tests Maven (`user-service`, `gateway`),
lint+build Vite, build/push GHCR (`nestora-user-service`, `nestora-gateway`, `nestora-frontend` + tag `:latest` + `:<sha>`),
scan Trivy HIGH/CRITICAL (SARIF, non bloquant au début).

Secrets requis côté repo GitHub : aucun pour GHCR public (`GITHUB_TOKEN` suffit).
Pour Docker Hub : ajouter `DOCKER_USERNAME` / `DOCKER_PASSWORD` et adapter (modèle existant dans `Nestora/gateway/.github/workflows/ci-gateway.yml`).

## 3. Kubernetes

```bash
cp k8s/base/secret.example.yaml k8s/base/secret.yaml  # remplir, fichier gitignoré
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/secret.yaml
kubectl apply -k k8s/base   # ou: kubectl apply -f k8s/base/*.yaml
kubectl -n nestora get pods,svc
kubectl -n nestora port-forward svc/frontend 8088:80   # front local sans ingress
```

Images par défaut : `ghcr.io/marouanof/nestora-*`. Remplace `marouanof` par ton owner GHCR si fork.
Ingress fourni pour cluster avec ingress-nginx ; sur la VM OCI, le NodePort 30080 est ouvert dans la security list.

## 4. Infra OCI Always Free (Terraform)

```bash
cd terraform/oci
cp terraform.tfvars.example terraform.tfvars   # remplir OCIDs + clé API + clé SSH
terraform init && terraform fmt -check && terraform validate
terraform plan -out plan.out
terraform apply plan.out
# -> output : k3s_public_ip, ssh_cmd, kubeconfig_cmd
ssh opc@<ip> "cat /root/k3s-ready.txt"
scp opc@<ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/nestora-oci.yaml
# édite server: https://<ip>:6443, puis :
kubectl --kubeconfig ~/.kube/nestora-oci.yaml -n nestora get nodes
```

Coût : 2 OCPU / 12 Go (défauts) dans le quota Always Free Ampere (4 OCPU / 24 Go). `terraform destroy` pour libérer.

## 5. Ce que ça prouve en entretien (à savoir expliquer)

- Layer Docker multi-stage : image runtime sans JDK/Maven/Node (~-70 % de taille), user non-root, HEALTHCHECK.
- `SPRING_PROFILES_ACTIVE=prod` : la conf vient des env vars (`application-prod.properties` / `application.yml`), jamais en dur.
- Gateway : routage + JWT + CORS centralisés ; le front appelle du relatif `/api` proxifié par Nginx (pas de CORS en prod).
- CI : test d'abord, tag immutable `:<sha>` + `:latest`, scan Trivy avant push.
- K8s : 1 Secret partagé, probes `/actuator/health`, requests/limits calibrés petite VM, PVC 5 Go.
- Terraform : réseau fermé par défaut, seuls 22/80/443/30080 ouverts, cloud-init idempotent, state local (backend OCI Object Storage en bonus).

## 6. Pour le CV / LinkedIn

- `Projet DevOps — Nestora Ops : conteneurisation multi-stage (Spring Boot 21, Vite/Nginx, Postgres 16), CI/CD GitHub Actions + GHCR + Trivy, IaC Terraform (OCI Always Free), déploiement Kubernetes (Kustomize, probes, secrets), observabilité Prometheus/Grafana.`
- Compétences : `Docker · GitHub Actions · Kubernetes · Terraform · OCI · Prometheus/Grafana · GHCR · Trivy`.

## 7. Roadmap honnête (ne pas claimer avant de l'avoir fait)

1. `micrometer-registry-prometheus` dans les poms -> scrape `/actuator/prometheus` au lieu du blackbox seul.
2. Conteneuriser property/booking/notification + RabbitMQ, vraies URIs gateway.
3. CD GitOps ArgoCD + 2 env (staging/prod) via Kustomize overlays.
4. Backend Terraform remote state (OCI Object Storage) + Vault/External Secrets.
