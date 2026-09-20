terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Optional but recommended: keep state in a GCS bucket so Terraform and CI
  # share it. Create the bucket first (gsutil mb), then uncomment and set it.
  # backend "gcs" {
  #   bucket = "YOUR-TFSTATE-BUCKET"
  #   prefix = "vrising/gke"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# APIs required by this stack. Enabling is idempotent.
resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "cloudscheduler.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "sts.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}
