# ZONAL cluster (location = a single zone) => control plane is on GKE's free tier.
# A regional cluster (location = a region) would incur the ~$0.10/hr management fee.
resource "google_container_cluster" "vrising" {
  name     = var.cluster_name
  location = var.zone

  # Run our own node pool; never use the default one.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  # VPC-native cluster using the subnet secondary ranges.
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Workload Identity (pod -> GCP IAM). Kept on even though this workload does
  # not need cloud APIs; it is the secure default and cheap to leave enabled.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  # Set to true once you are in production and want to guard against deletion.
  deletion_protection = false

  depends_on = [google_project_service.services]
}

resource "google_container_node_pool" "game" {
  name     = var.node_pool_name
  location = var.zone
  cluster  = google_container_cluster.vrising.name

  # Managed directly (via Cloud Scheduler setSize), not by the cluster autoscaler.
  node_count = 1

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD"

    # Network tag targeted by the game/RCON firewall rules.
    tags = ["vrising-node"]

    # Minimal scopes; Workload Identity is the auth path for anything else.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      workload = "vrising"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # The scale-up/down scheduler jobs change node_count out of band; don't let
  # Terraform fight them on the next apply.
  lifecycle {
    ignore_changes = [node_count]
  }
}
