# Wiz Technical Exercise (GCP)

Two-tier web app (Tasky + MongoDB) on Google Cloud, deployed end to end from GitHub Actions, with intentional misconfigurations and the controls that catch them.

```
Internet ──► HTTP(S) Load Balancer ──► GKE Ingress ──► Tasky pods (private subnet, cluster-admin SA)
                                                           │  MONGODB_URI (K8s Secret ◄─ Secret Manager)
                                                           ▼
Internet ──SSH:22──► MongoDB 4.4 VM, Ubuntu 20.04 (public subnet, roles/compute.admin)
                                                           │  daily mongodump (cron)
                                                           ▼
                                          GCS bucket ◄── allUsers: list + read
```

| Path                          | What it is                                                                                                                 |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `terraform/`                  | VPC, private GKE, MongoDB VM, backup bucket, Artifact Registry, Secret Manager, audit logs, Binary Authorization, alerting |
| `app/`                        | Tasky (Go) with `wizexercise.txt` added to the image                                                                       |
| `k8s/`                        | Namespace, cluster-admin binding, Deployment, Service, Ingress                                                             |
| `.github/workflows/infra.yml` | Checkov scan → plan → approved apply (or destroy)                                                                          |
| `.github/workflows/app.yml`   | Build → verify `wizexercise.txt` → Trivy scan → push → deploy → verify in running pod                                      |
| `scripts/bootstrap.sh`        | One-time: state bucket + Workload Identity Federation for GitHub                                                           |
| `scripts/demo.sh`             | Live demo commands                                                                                                         |

## Intentional weaknesses

| Resource      | Weakness                                                                                             |
| ------------- | ---------------------------------------------------------------------------------------------------- |
| MongoDB VM    | Ubuntu 20.04, MongoDB 4.4 (EOL), SSH open to `0.0.0.0/0`, service account with `roles/compute.admin` |
| Backup bucket | `allUsers` has `roles/storage.objectViewer` (public list + read)                                     |
| Tasky         | ServiceAccount bound to `cluster-admin`; outdated base images and Go dependencies                    |
| GKE API       | Control plane endpoint reachable from any IP                                                         |

## Security controls

| Type       | Control                                                                                 |
| ---------- | --------------------------------------------------------------------------------------- |
| Audit      | Cloud Audit Logs: Admin Activity + Data Access for all services                         |
| Preventive | Binary Authorization: only images from this project's Artifact Registry can run on GKE  |
| Preventive | Pipelines: OIDC auth (no keys), approval on `production` environment, branch protection |
| Detective  | Log-based metric + alert on firewall changes, IAM policy changes and `kubectl exec`     |
| Detective  | Checkov (IaC) and Trivy (image) results in GitHub Security tab                          |

test commit
