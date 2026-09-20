output "cluster_name" {
  value       = google_container_cluster.vrising.name
  description = "GKE cluster name (use with: gcloud container clusters get-credentials)."
}

output "cluster_location" {
  value       = google_container_cluster.vrising.location
  description = "GKE cluster location (zone)."
}

output "node_pool_name" {
  value       = google_container_node_pool.game.name
  description = "Node pool resized by the scale-up/down scheduler jobs."
}

output "static_ip" {
  value       = google_compute_address.vrising.address
  description = "Reserved external IP. Put this in k8s/overlays/gke/patches/service-ip.yaml as loadBalancerIP and share it with players (direct connect on :9876)."
}

output "workload_identity_provider" {
  value       = google_iam_workload_identity_pool_provider.github.name
  description = "Set as the GitHub secret WIF_PROVIDER (used by deploy.yml)."
}

output "deployer_service_account" {
  value       = google_service_account.deployer.email
  description = "Set as the GitHub secret WIF_SERVICE_ACCOUNT (used by deploy.yml)."
}
