# Demo en orden del panel

# ======================================================================
# 1.- La app está expuesta por un load balancer (IP para compartir)
# ======================================================================
# Ingress de Kubernetes con la IP pública
kubectl -n tasky get ingress tasky

# ======================================================================
# 2.- El cluster está en una subred privada
# ======================================================================
# Los nodos no tienen IP pública: la columna EXTERNAL-IP sale <none>
kubectl get nodes -o wide

# ======================================================================
# 3.- El archivo wizexercise.txt existe en la imagen y en el contenedor
# ======================================================================
kubectl -n tasky exec deploy/tasky -- cat /app/wizexercise.txt

# ======================================================================
# 4.- La aplicación tiene rol de administradora del cluster
# ======================================================================
# El pod usa la ServiceAccount tasky
kubectl -n tasky get pods -l app=tasky -o custom-columns=POD:.metadata.name,SA:.spec.serviceAccountName

# Esa ServiceAccount está enlazada a cluster-admin
kubectl get clusterrolebinding tasky-cluster-admin -o wide

# Puede hacer cualquier cosa en todo el cluster
kubectl auth can-i '*' '*' --as=system:serviceaccount:tasky:tasky

# ======================================================================
# 5. Los datos están en la base de datos (conexión SSH a la VM)
# ======================================================================
# SSH abierto a internet: esta es una de las debilidades
gcloud compute ssh wiz-mongo --zone us-east4-a

# Correr en terminal desde mi computadora
ssh admin@34.85.221.128

# ======================================================================
# 6. Mongo solo es accesible desde Kubernetes
# ======================================================================
# Reglas de firewall de la VPC: SSH desde 0.0.0.0/0, Mongo solo desde rangos de GKE
gcloud compute firewall-rules list --filter="network~wiz-vpc" \
  --format="table(name, sourceRanges.list(), allowed[].map().firewall_rule().list())"

# ======================================================================
# 7. La identidad de la VM puede crear VMs (movimiento lateral)
# ======================================================================
# Rol asignado a la service account de la VM
gcloud projects get-iam-policy clgcporg10-146 --flatten="bindings[].members" \
  --filter="bindings.members~wiz-mongo-vm" --format="table(bindings.role, bindings.members)"

# Desde dentro de la VM, con sus propias credenciales, ve y controla todas las VMs
gcloud compute ssh wiz-mongo --zone us-east4-a --command "gcloud compute instances list"

# ======================================================================
# 8. Los backups son públicos (el mayor riesgo)
# ======================================================================
# Lanza un backup ahora para que incluya los datos del panel
gcloud compute ssh wiz-mongo --zone us-east4-a --command "sudo /usr/local/bin/mongo-backup.sh"


# ======================================================================
# 9.- Control Auditoría: Audit logs
# ======================================================================
# Configuración de Audit logs para todos los servicios (security.tf)
gcloud projects get-iam-policy clgcporg10-146 --format=json | jq '.auditConfigs'

# ======================================================================
# 10.- Control preventivo: Binary Authorization
# ======================================================================
# Imagen de fuera de nuestro registro: rechazada
kubectl run nginx-test --image=nginx -n tasky

# ======================================================================
# 11.- Auditoría y control detectivo
# ======================================================================

# Detectivo: un cambio en el firewall que expone SSH dispara la alerta por email
gcloud compute firewall-rules update wiz-allow-ssh-public --description="demo panel"
