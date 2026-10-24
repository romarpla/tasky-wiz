output "cluster_name" {
  value = google_container_cluster.gke.name
}

output "cluster_location" {
  value = google_container_cluster.gke.location
}

output "image_repo" {
  value = local.image_repo
}

output "mongo_vm_name" {
  value = google_compute_instance.mongo.name
}

output "mongo_public_ip" {
  value = google_compute_address.mongo.address
}

output "mongo_private_ip" {
  value = google_compute_instance.mongo.network_interface[0].network_ip
}

output "backup_bucket_url" {
  value = "https://storage.googleapis.com/${google_storage_bucket.backups.name}"
}

output "mongo_admin_password" {
  value     = random_password.mongo_admin.result
  sensitive = true
}
