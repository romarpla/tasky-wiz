#!/bin/bash
# Commands for the live demo, in order. Run them one by one, not as a script.
# Prerequisite: gcloud auth login && gcloud config set project <project-id>

# 0. Connect kubectl to the cluster
gcloud container clusters get-credentials wiz-gke --zone us-central1-a

# 1. Cluster nodes have only internal IPs (private subnet)
kubectl get nodes -o wide

# 2. Everything the app runs on, plus the public IP of the load balancer
kubectl get pods,svc,ingress -n tasky -o wide

# 3. wizexercise.txt exists inside the running container
kubectl -n tasky exec deploy/tasky -- cat /app/wizexercise.txt

# 4. MongoDB connection comes from an environment variable
kubectl -n tasky get deploy tasky -o jsonpath='{.spec.template.spec.containers[0].env}' ; echo
kubectl -n tasky exec deploy/tasky -- printenv MONGODB_URI

# 5. The app's service account is cluster-admin (and what that allows)
kubectl get clusterrolebinding tasky-cluster-admin -o wide
kubectl auth can-i '*' '*' --as=system:serviceaccount:tasky:tasky

# 6. The data is in MongoDB (SSH is open to the internet)
gcloud compute ssh wiz-mongo --zone us-central1-a
#   then on the VM:
#   lsb_release -d && mongod --version | head -1
#   mongo -u admin -p '<password from: terraform output -raw mongo_admin_password>' --authenticationDatabase admin
#   > use go-mongodb
#   > db.todos.find().pretty()
#   > db.user.find({}, {name: 1, email: 1})

# 7. Backups are public: anyone can list and download them
curl -s "$(cd terraform && terraform output -raw backup_bucket_url)" | head -c 600; echo

# 8. Preventive control: an image outside our registry is rejected by Binary Authorization
kubectl run nginx-test --image=nginx -n tasky

# 9. Detective control: the exec from step 3 and any firewall change show up in audit logs
gcloud logging read 'protoPayload.methodName="io.k8s.core.v1.pods.exec.create"' --limit 3 --format='table(timestamp,protoPayload.authenticationInfo.principalEmail)'

# 10. The VM's identity can create VMs (lateral movement / cryptomining risk), from inside the VM:
#   gcloud compute instances list
