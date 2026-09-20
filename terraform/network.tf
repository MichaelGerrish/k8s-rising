# Custom VPC (VPC-native / alias IPs for the GKE cluster).
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.services]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  # Secondary ranges consumed by the VPC-native cluster (pods + services).
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

# Reserved regional external IP used as the LoadBalancer address, so the
# player-facing endpoint is stable across nightly node recreation.
resource "google_compute_address" "vrising" {
  name         = "${var.cluster_name}-ip"
  region       = var.region
  address_type = "EXTERNAL"
  depends_on   = [google_project_service.services]
}

# Allow inbound game traffic to the nodes. GKE also manages LB firewall rules
# automatically, but this is explicit and also covers RCON if you enable it.
resource "google_compute_firewall" "vrising_game" {
  name    = "${var.cluster_name}-allow-game"
  network = google_compute_network.vpc.id

  allow {
    protocol = "udp"
    ports    = ["9876", "9877"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["vrising-node"]
}

# Optional: RCON. Lock source_ranges down to your admin IP before enabling.
resource "google_compute_firewall" "vrising_rcon" {
  name    = "${var.cluster_name}-allow-rcon"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["25575"]
  }

  # Tighten this to your own /32 before relying on RCON.
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["vrising-node"]
  disabled      = true
}
