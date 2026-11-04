#!/bin/bash
# Live demo commands, in order. Copy and paste block by block; do not run as a script.
# Full walkthrough with expected output and talking points: docs/DEMO.md

# ======================================================================
# 0. Preparación (antes de compartir pantalla)
# ======================================================================
gcloud config set project clgcporg10-146
gcloud container clusters get-credentials wiz-gke --zone us-east4-a
cd ~/tasky-wiz

# Variables que usan los bloques siguientes
LB_IP=$(kubectl -n tasky get ingress tasky -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
VM_IP=$(gcloud compute instances describe wiz-mongo --zone us-east4-a --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
BUCKET=wiz-mongo-backups-ddebda
echo "App: http://$LB_IP   VM: $VM_IP"

cd ~/tasky-wiz/terraform
terraform init -backend-config="bucket=clgcporg10-146-tfstate" >/dev/null
terraform output -raw mongo_admin_password; echo
cd ~/tasky-wiz

# ======================================================================
# 1. El cluster está en una subred privada
# ======================================================================
# Los nodos no tienen IP pública: la columna EXTERNAL-IP sale <none>
kubectl get nodes -o wide

# GKE confirma nodos privados y en qué subred viven
gcloud container clusters describe wiz-gke --zone us-east4-a \
  --format="table(privateClusterConfig.enablePrivateNodes, subnetwork, privateClusterConfig.masterIpv4CidrBlock)"

# Rango de la subred privada (10.0.2.0/24): coincide con las INTERNAL-IP de los nodos
gcloud compute networks subnets describe wiz-private --region us-east4 --format="value(ipCidrRange)"

# Las VMs de los nodos: sin IP externa; compárala con wiz-mongo, que sí tiene
gcloud compute instances list --format="table(name, networkInterfaces[0].networkIP, networkInterfaces[0].accessConfigs[0].natIP)"

# ======================================================================
# 2. El archivo wizexercise.txt existe en la imagen y en el contenedor
# ======================================================================
# Cómo entró: la línea COPY del Dockerfile
grep -n wizexercise app/Dockerfile

# Qué imagen está corriendo (de nuestro Artifact Registry, etiquetada con el commit)
kubectl -n tasky get deploy tasky -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

# El archivo dentro del contenedor en ejecución
kubectl -n tasky exec deploy/tasky -- ls -l /app/wizexercise.txt
kubectl -n tasky exec deploy/tasky -- cat /app/wizexercise.txt

# ======================================================================
# 3. La aplicación tiene rol de administradora del cluster
# ======================================================================
# El pod usa la ServiceAccount tasky
kubectl -n tasky get pods -l app=tasky -o custom-columns=POD:.metadata.name,SA:.spec.serviceAccountName

# Esa ServiceAccount está enlazada a cluster-admin
kubectl get clusterrolebinding tasky-cluster-admin -o wide

# Puede hacer cualquier cosa en todo el cluster
kubectl auth can-i '*' '*' --as=system:serviceaccount:tasky:tasky

# Impacto: con esa identidad se leen los secretos de TODOS los namespaces
kubectl get secrets -A --as=system:serviceaccount:tasky:tasky | head

# ======================================================================
# 4. La app está expuesta por un load balancer (IP para compartir)
# ======================================================================
# Ingress de Kubernetes con la IP pública
kubectl -n tasky get ingress tasky

# El load balancer real que creó GCP (forwarding rule con la misma IP)
gcloud compute forwarding-rules list --format="table(name, IPAddress, portRange, target.basename())"

# Responde desde internet
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$LB_IP/

# URL para pegar en el chat del Zoom
echo "http://$LB_IP"

# ======================================================================
# 5. Los datos están en la base de datos (conexión SSH a la VM)
# ======================================================================
# SSH abierto a internet: esta es una de las debilidades
gcloud compute ssh wiz-mongo --zone us-east4-a

# --- EN LA VM (después del gcloud compute ssh) ---
# SO y base de datos desactualizados
lsb_release -d
mongod --version | head -1
apt list --upgradable 2>/dev/null | wc -l     # paquetes pendientes de parche

# Mongo exige autenticación: sin credenciales no deja leer
mongosh go-mongodb --quiet --eval 'db.todos.find()'

# Con credenciales: las tareas y los usuarios creados desde la app
mongosh -u admin -p '<PASSWORD>' --authenticationDatabase admin go-mongodb --quiet --eval '
  print("todos: " + db.todos.countDocuments());
  printjson(db.todos.find().toArray());
  printjson(db.user.find({}, {name: 1, email: 1}).toArray());'

# Backup diario programado
cat /etc/cron.d/mongo-backup

# ======================================================================
# 6. Mongo solo es accesible desde Kubernetes
# ======================================================================
# Reglas de firewall de la VPC: SSH desde 0.0.0.0/0, Mongo solo desde rangos de GKE
gcloud compute firewall-rules list --filter="network~wiz-vpc" \
  --format="table(name, sourceRanges.list(), allowed[].map().firewall_rule().list())"

# Desde internet (Cloud Shell): el 22 responde, el 27017 no
timeout 5 bash -c "</dev/tcp/$VM_IP/22" && echo "22 ABIERTO" || echo "22 cerrado"
timeout 5 bash -c "</dev/tcp/$VM_IP/27017" && echo "27017 ABIERTO" || echo "27017 cerrado/filtrado"

# La app recibe la conexión por variable de entorno (contraseña enmascarada)
kubectl -n tasky exec deploy/tasky -- printenv MONGODB_URI | sed -E 's#(://[^:]+:)[^@]+@#\1****@#'

# ======================================================================
# 7. Los backups son públicos (el mayor riesgo)
# ======================================================================
# Listado público sin credenciales (también: abre la URL en incógnito)
curl -s https://storage.googleapis.com/$BUCKET | grep -o '<Key>[^<]*</Key>'

# Lanza un backup ahora para que incluya los datos del panel
gcloud compute ssh wiz-mongo --zone us-east4-a --command "sudo /usr/local/bin/mongo-backup.sh"

# Como "atacante": descarga el último backup sin autenticarse y mira qué contiene
LATEST=$(curl -s https://storage.googleapis.com/$BUCKET | grep -o 'backups/[^<]*' | sort | tail -1)
curl -s -o /tmp/leak.archive.gz "https://storage.googleapis.com/$BUCKET/$LATEST"
ls -lh /tmp/leak.archive.gz
gunzip -c /tmp/leak.archive.gz | strings | grep -E '@|\$2a\$' | head

# ======================================================================
# 8. La identidad de la VM puede crear VMs (movimiento lateral)
# ======================================================================
# Rol asignado a la service account de la VM
gcloud projects get-iam-policy clgcporg10-146 --flatten="bindings[].members" \
  --filter="bindings.members~wiz-mongo-vm" --format="table(bindings.role, bindings.members)"

# Desde dentro de la VM, con sus propias credenciales, ve y controla todas las VMs
gcloud compute ssh wiz-mongo --zone us-east4-a --command "gcloud compute instances list"

# ======================================================================
# 9. Control preventivo: Binary Authorization
# ======================================================================
# Imagen de fuera de nuestro registro: rechazada
kubectl run nginx-test --image=nginx -n tasky

# Política que lo impone
gcloud container binauthz policy export | grep -A3 -E "admissionWhitelistPatterns|defaultAdmissionRule"

# ======================================================================
# 10. Auditoría y control detectivo
# ======================================================================
# Auditoría: el kubectl exec de la sección 2 queda registrado (quién y cuándo)
gcloud logging read 'protoPayload.methodName=~"io.k8s.core.v1.pods.exec"' --freshness=1h --limit 3 \
  --format='table(timestamp, protoPayload.methodName, protoPayload.authenticationInfo.principalEmail)'

# Detectivo: un cambio en el firewall que expone SSH dispara la alerta por email
gcloud compute firewall-rules update wiz-allow-ssh-public --description="demo $(date +%s)"
