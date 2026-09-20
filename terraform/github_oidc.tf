# Keyless auth for GitHub Actions via Workload Identity Federation.
# No long-lived JSON service-account key ever leaves GCP.

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "${var.cluster_name}-gh-pool"
  display_name              = "GitHub Actions (V Rising)"
  depends_on                = [google_project_service.services]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # Only tokens from the specified repo are accepted by this provider.
  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service account the GitHub workflow impersonates to run kubectl against GKE.
resource "google_service_account" "deployer" {
  account_id   = "${var.cluster_name}-deployer"
  display_name = "V Rising GitHub Actions deployer"
}

# container.developer can deploy workloads but not manage the cluster itself.
resource "google_project_iam_member" "deployer_container" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# Allow the specific repo (any branch) to impersonate the deployer SA.
resource "google_service_account_iam_member" "deployer_wif" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}
