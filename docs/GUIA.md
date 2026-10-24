# Guía paso a paso (GCP)

Esta guía explica qué hace cada pieza del repositorio y en qué orden desplegarla. Calcula unas 3 a 4 horas para el primer despliegue completo, más el tiempo de resolver imprevistos (que luego son material para la diapositiva de retos).

## 0. Antes de empezar

1. Activa el voucher de Wiz CloudLabs y anota el **project ID** de GCP que te den.
2. Crea un repositorio en GitHub (puede ser público: así el escaneo de seguridad de GitHub es gratis) y sube el contenido de esta carpeta a la rama `main`.
3. En `app/wizexercise.txt` pon tu nombre completo.
4. En `.github/CODEOWNERS` cambia `@OWNER` por tu usuario de GitHub.

## 1. Bootstrap: conectar GitHub con GCP (una sola vez)

Abre **Cloud Shell** en la consola de GCP (ya trae `gcloud`, `kubectl` y `terraform`), clona tu repo y ejecuta:

```bash
./scripts/bootstrap.sh <project-id> <tu-usuario>/<tu-repo>
```

Qué hace y por qué:

- **Bucket de estado de Terraform** (`<project-id>-tfstate`): guarda el estado de la infraestructura fuera de tu portátil, versionado y nunca público. Así el pipeline sabe qué existe.
- **Service account `github-deployer`**: la identidad con la que el pipeline crea recursos. Tiene roles amplios (editor, IAM admin, etc.) porque Terraform tiene que poder dar permisos. Es un buen tema de conversación: en producción lo dividirías por pipeline y le quitarías permisos.
- **Workload Identity Federation**: GitHub Actions obtiene un token OIDC de corta duración y GCP lo cambia por credenciales temporales. **No hay claves JSON guardadas en GitHub**, y la condición `assertion.repository=='<tu-repo>'` impide que otro repo use esa identidad. Este es uno de tus controles de seguridad del pipeline.

Al final el script imprime 4 valores. Crea estas **variables de repositorio** en GitHub (Settings → Secrets and variables → Actions → Variables): `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_SA_EMAIL`, `TF_STATE_BUCKET`, y añade `ALERT_EMAIL` con tu correo.

## 2. Seguridad del repositorio en GitHub

En Settings del repo:

1. **Environments → New environment `production`** → marca *Required reviewers* y añádete. Cada `apply` y cada despliegue esperará tu aprobación manual.
2. **Branches → Add rule para `main`**: exigir pull request, 1 aprobación, revisión de CODEOWNERS y que los checks pasen.
3. **Code security**: activa Dependabot alerts, secret scanning y push protection.

Haz capturas de esta configuración: van en la diapositiva de "How you built it".

## 3. Infraestructura con Terraform (`terraform/`)

Cada archivo es una pieza del diagrama:

| Archivo | Qué crea | Detalle importante |
| --- | --- | --- |
| `versions.tf` | Proveedores y backend | El estado se guarda en el bucket del bootstrap |
| `apis.tf` | Activa las APIs de GCP necesarias | Sin esto los demás recursos fallan en un proyecto nuevo |
| `network.tf` | VPC, subred pública `10.0.1.0/24`, subred privada `10.0.2.0/24`, Cloud NAT, firewalls | El firewall de Mongo solo acepta tráfico desde los rangos de nodos y pods de GKE; el de SSH acepta `0.0.0.0/0` (**debilidad**) |
| `gke.tf` | Cluster GKE privado con 2 nodos | `enable_private_nodes`: los nodos no tienen IP pública. Binary Authorization activado (**control preventivo**) |
| `vm.tf` | VM `wiz-mongo` con Ubuntu 20.04 e IP pública | Su service account tiene `roles/compute.admin` (**debilidad**: puede crear VMs) |
| `scripts/mongo-startup.sh.tftpl` | Script de arranque de la VM | Instala MongoDB 4.4 (fin de soporte feb 2024), crea usuario `admin` y usuario `tasky`, activa autenticación y programa el backup diario a las 02:00 UTC |
| `storage.tf` | Bucket de backups | `allUsers` con `objectViewer`: cualquiera puede listar y descargar (**debilidad**) |
| `registry.tf` | Artifact Registry `tasky` | Donde el pipeline sube la imagen |
| `secrets.tf` | Secret Manager con `MONGODB_URI` y `SECRET_KEY` | Las contraseñas las genera Terraform; nunca están en git |
| `security.tf` | Audit logs, política de Binary Authorization, métrica y alerta | Ver sección 6 |
| `outputs.tf` | IPs, URL del bucket, contraseña admin de Mongo | `terraform output -raw mongo_admin_password` para la demo |

**Cómo se despliega:** haz un cambio en `terraform/` en una rama y abre un PR. El workflow `infra.yml` corre Checkov y `terraform plan`. Al hacer merge a `main` vuelve a planificar y espera tu aprobación en el environment `production` antes de `apply`. Para desplegar la primera vez sin PR, usa **Actions → Infrastructure → Run workflow → apply**. El primer apply tarda unos 15 minutos, casi todo por GKE.

Comprobación: en la consola verás la VM, el cluster y el bucket. Espera 3 o 4 minutos a que el script de arranque instale Mongo; puedes seguirlo con `gcloud compute ssh wiz-mongo --zone us-central1-a` y `sudo journalctl -u google-startup-scripts -f`.

## 4. La aplicación (`app/`)

Es Tasky sin cambios de código. Solo cambia el `Dockerfile`, con una línea nueva:

```dockerfile
COPY wizexercise.txt /app/wizexercise.txt
```

Así es como entra el archivo en la imagen. El pipeline lo valida dos veces: con `docker run ... cat` justo después del build, y con `kubectl exec ... cat` sobre el pod ya en ejecución. En la demo repites el segundo.

La app lee `MONGODB_URI` y `SECRET_KEY` de variables de entorno, así que no hay que tocar el código para conectarla a la VM.

## 5. Kubernetes y pipeline de la app (`k8s/`, `app.yml`)

| Manifiesto | Qué hace |
| --- | --- |
| `namespace.yaml` | Namespace `tasky` |
| `rbac.yaml` | ServiceAccount `tasky` + ClusterRoleBinding a `cluster-admin` (**debilidad** pedida por el enunciado) |
| `deployment.yaml` | 2 réplicas; `MONGODB_URI` y `SECRET_KEY` como variables de entorno que vienen de un Secret |
| `service.yaml` | Service ClusterIP con NEG, que es lo que GKE usa para enrutar desde el load balancer directo a los pods |
| `ingress.yaml` | Ingress clase `gce`: GKE crea un HTTP(S) Load Balancer público |

El workflow `app.yml` hace, en orden: build de la imagen, comprobación de `wizexercise.txt`, escaneo con Trivy (resultados en la pestaña Security de GitHub), push a Artifact Registry, y luego, con aprobación, crea el Secret de Kubernetes leyendo Secret Manager, aplica los manifiestos y valida el archivo en el pod.

La IP pública del load balancer aparece con `kubectl get ingress -n tasky` unos 5 minutos después del primer despliegue.

**Sobre los escáneres:** Checkov y Trivy están en modo "reportar" porque el entorno es inseguro a propósito y bloquearían todo. Para la demo, pon la variable de repo `IMAGE_SCAN_GATE=true` (o `IAC_SCAN_SOFT_FAIL=false`), lanza el workflow y enseña cómo el pipeline se pone en rojo y no despliega. Así demuestras que el control funciona y explicas la decisión de aceptar el riesgo.

## 6. Controles nativos de GCP (`security.tf`)

| Requisito | Implementación | Cómo enseñarlo |
| --- | --- | --- |
| Audit logging del plano de control | Admin Activity siempre activo + Data Access para todos los servicios | Logs Explorer: filtra por `logName:"cloudaudit.googleapis.com"` |
| Control preventivo | Binary Authorization: solo se admiten imágenes de tu Artifact Registry | `kubectl run nginx-test --image=nginx -n tasky` → rechazado |
| Control detectivo | Métrica de logs + alerta por email ante cambios de firewall, de IAM o `kubectl exec` | Haz un `kubectl exec` en la demo y enseña el correo o el incidente en Monitoring |
| Extra opcional | Security Command Center (actívalo en la consola si CloudLabs lo permite) | Hallazgos como `OPEN_SSH_PORT` o `PUBLIC_BUCKET_ACL` |

## 7. Probar la demo y apagar

`scripts/demo.sh` tiene los comandos de la demo en orden, cada uno con un comentario que dice qué requisito prueba. Ensáyalos al menos una vez de principio a fin.

Para borrar todo al terminar: **Actions → Infrastructure → Run workflow → destroy**.

## Problemas que pueden aparecer (apúntalos si te pasan)

- **Políticas de organización de CloudLabs**: el proyecto puede tener restricciones como `iam.allowedPolicyMemberDomains` (bloquea `allUsers` en el bucket) o `compute.vmExternalIpAccess`. Si `apply` falla con un error de "constraint", ese es el motivo y es un buen reto para contar.
- **Cuotas**: si falla por CPUs o IPs, baja los nodos a 1 o usa `e2-medium`.
- **El load balancer devuelve 502 los primeros minutos**: es normal mientras pasan los health checks.
- **La app no conecta a Mongo**: comprueba en la VM que `mongod` está activo y que el firewall incluye el rango de pods `10.4.0.0/14`.
