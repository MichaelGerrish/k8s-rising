variable "project_id" {
  type        = string
  description = "GCP project ID to deploy into."
}

variable "region" {
  type        = string
  description = "GCP region for regional resources (subnet, static IP, scheduler)."
  default     = "us-west4"
}

variable "zone" {
  type        = string
  description = "GCP zone for the GKE cluster. A ZONAL cluster keeps the control plane on GKE's free tier (the free-tier credit is region-agnostic). us-west4 (Las Vegas) is the closest region to Arizona; it runs ~10% higher than us-central1 on compute but cuts player latency substantially."
  default     = "us-west4-a"
}

variable "cluster_name" {
  type        = string
  description = "Name of the GKE cluster."
  default     = "vrising"
}

variable "node_pool_name" {
  type        = string
  description = "Name of the game node pool (referenced by the scale-up/down Cloud Scheduler jobs)."
  default     = "game"
}

variable "machine_type" {
  type        = string
  description = "Node machine type. e2-standard-4 = 4 vCPU / 16Gi (amd64, has AVX). e2-standard-2 (2 vCPU/8Gi) is a cheaper option for small groups."
  default     = "e2-standard-4"
}

variable "node_disk_size_gb" {
  type        = number
  description = "Boot disk size for the node."
  default     = 50
}

variable "github_repo" {
  type        = string
  description = "GitHub repo allowed to deploy via Workload Identity Federation, as 'owner/name'."
}

# --- Scheduled scale-down ---------------------------------------------------

variable "enable_scheduled_scaling" {
  type        = bool
  description = "Create Cloud Scheduler jobs that scale the node pool to 0 at night and back to 1 in the morning."
  default     = true
}

variable "scale_down_cron" {
  type        = string
  description = "Cron (in scheduler_time_zone) to scale the node pool to 0."
  default     = "0 3 * * *"
}

variable "scale_up_cron" {
  type        = string
  description = "Cron (in scheduler_time_zone) to scale the node pool back to 1."
  default     = "0 16 * * *"
}

variable "scheduler_time_zone" {
  type        = string
  description = "IANA time zone the scale-up/down crons are evaluated in. America/Phoenix (Arizona) does not observe DST, so the schedule never drifts."
  default     = "America/Phoenix"
}
