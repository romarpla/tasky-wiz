resource "random_password" "mongo_admin" {
  length  = 24
  special = false
}

resource "random_password" "mongo_app" {
  length  = 24
  special = false
}

resource "google_service_account" "mongo_vm" {
  account_id   = "${var.prefix}-mongo-vm"
  display_name = "MongoDB VM"
}

# INTENTIONAL WEAKNESS: the VM identity can create and delete any VM in the project
resource "google_project_iam_member" "mongo_vm_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.mongo_vm.email}"
}

resource "google_compute_address" "mongo" {
  name   = "${var.prefix}-mongo-ip"
  region = var.region
}

resource "google_compute_instance" "mongo" {
  name         = "${var.prefix}-mongo"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["mongodb"]

  boot_disk {
    initialize_params {
      # INTENTIONAL WEAKNESS: Ubuntu 20.04 (2020), past end of standard support
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id
    access_config {
      nat_ip = google_compute_address.mongo.address
    }
  }

  service_account {
    email  = google_service_account.mongo_vm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = templatefile("${path.module}/scripts/mongo-startup.sh.tftpl", {
    admin_password = random_password.mongo_admin.result
    app_password   = random_password.mongo_app.result
    backup_bucket  = google_storage_bucket.backups.name
  })

  depends_on = [google_compute_router_nat.nat]
}
