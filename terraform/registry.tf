resource "google_artifact_registry_repository" "tasky" {
  repository_id = "tasky"
  location      = var.region
  format        = "DOCKER"
  depends_on    = [google_project_service.services]
}

locals {
  image_repo = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.tasky.repository_id}"
}
