resource "google_compute_network" "vpc" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.services]
}

# Public subnet: the MongoDB VM lives here with an external IP
resource "google_compute_subnetwork" "public" {
  name          = "${var.prefix}-public"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Private subnet: GKE nodes have no external IPs
resource "google_compute_subnetwork" "private" {
  name                     = "${var.prefix}-private"
  ip_cidr_range            = "10.0.2.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }
}

# Outbound internet for private nodes (pull images, updates)
resource "google_compute_router" "router" {
  name    = "${var.prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.prefix}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# INTENTIONAL WEAKNESS: SSH open to the whole internet
resource "google_compute_firewall" "ssh_public" {
  name          = "${var.prefix}-allow-ssh-public"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mongodb"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# MongoDB only reachable from the GKE node and pod ranges
resource "google_compute_firewall" "mongo_from_gke" {
  name      = "${var.prefix}-allow-mongo-from-gke"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  source_ranges = [
    google_compute_subnetwork.private.ip_cidr_range,
    google_compute_subnetwork.private.secondary_ip_range[0].ip_cidr_range,
  ]
  target_tags = ["mongodb"]

  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }
}
