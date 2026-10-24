resource "random_id" "suffix" {
  byte_length = 3
}

resource "google_storage_bucket" "backups" {
  name                        = "${var.prefix}-mongo-backups-${random_id.suffix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "inherited"
  force_destroy               = true
}

# INTENTIONAL WEAKNESS: anyone on the internet can list and read the backups
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# The VM writes its daily dumps here
resource "google_storage_bucket_iam_member" "vm_writer" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.mongo_vm.email}"
}
