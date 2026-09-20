# Service account used by Cloud Scheduler to resize the node pool.
resource "google_service_account" "scaler" {
  count        = var.enable_scheduled_scaling ? 1 : 0
  account_id   = "${var.cluster_name}-scaler"
  display_name = "V Rising node pool scaler (Cloud Scheduler)"
}

# clusterAdmin includes container.clusters.update, which setSize requires.
resource "google_project_iam_member" "scaler" {
  count   = var.enable_scheduled_scaling ? 1 : 0
  project = var.project_id
  role    = "roles/container.clusterAdmin"
  member  = "serviceAccount:${google_service_account.scaler[0].email}"
}

locals {
  set_size_url = "https://container.googleapis.com/v1/projects/${var.project_id}/locations/${var.zone}/clusters/${var.cluster_name}/nodePools/${var.node_pool_name}:setSize"
}

# Scale the node pool to 0 at night (pod goes Pending, zero compute billed).
resource "google_cloud_scheduler_job" "scale_down" {
  count       = var.enable_scheduled_scaling ? 1 : 0
  name        = "${var.cluster_name}-scale-down"
  description = "Set the V Rising node pool to 0 nodes"
  schedule    = var.scale_down_cron
  time_zone   = var.scheduler_time_zone
  region      = var.region

  http_target {
    http_method = "POST"
    uri         = local.set_size_url
    headers     = { "Content-Type" = "application/json" }
    body        = base64encode(jsonencode({ nodeCount = 0 }))

    oauth_token {
      service_account_email = google_service_account.scaler[0].email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_project_service.services, google_container_node_pool.game]
}

# Scale the node pool back to 1 in the morning (pod reschedules; SteamCMD
# re-validates and Wine restarts -> ~5-10 min warm-up, which is expected).
resource "google_cloud_scheduler_job" "scale_up" {
  count       = var.enable_scheduled_scaling ? 1 : 0
  name        = "${var.cluster_name}-scale-up"
  description = "Set the V Rising node pool to 1 node"
  schedule    = var.scale_up_cron
  time_zone   = var.scheduler_time_zone
  region      = var.region

  http_target {
    http_method = "POST"
    uri         = local.set_size_url
    headers     = { "Content-Type" = "application/json" }
    body        = base64encode(jsonencode({ nodeCount = 1 }))

    oauth_token {
      service_account_email = google_service_account.scaler[0].email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_project_service.services, google_container_node_pool.game]
}
