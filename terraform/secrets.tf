resource "random_password" "jwt" {
  length  = 32
  special = false
}

locals {
  mongodb_uri = "mongodb://tasky:${random_password.mongo_app.result}@${google_compute_instance.mongo.network_interface[0].network_ip}:27017/go-mongodb?authSource=go-mongodb"
}

# The app pipeline reads these and turns them into a Kubernetes Secret
resource "google_secret_manager_secret" "mongodb_uri" {
  secret_id = "tasky-mongodb-uri"
  replication {
    auto {}
  }
  depends_on = [google_project_service.services]
}

resource "google_secret_manager_secret_version" "mongodb_uri" {
  secret      = google_secret_manager_secret.mongodb_uri.id
  secret_data = local.mongodb_uri
}

resource "google_secret_manager_secret" "jwt" {
  secret_id = "tasky-secret-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.services]
}

resource "google_secret_manager_secret_version" "jwt" {
  secret      = google_secret_manager_secret.jwt.id
  secret_data = random_password.jwt.result
}
