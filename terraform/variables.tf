###############################################################################
# General project settings
###############################################################################
variable "app_id" {
  description = "Application ID to identify GCP resources"
  type        = string
  default     = "llmdoc"
}

variable "google_project" {
  description = "GCP Project Id"
  type        = string
  default     = "lab5-llmdoc-dev1"
}

variable "google_region" {
  description = "Default GCP region"
  type        = string
  default     = "us-east5"
}

variable "gke_machine_type" {
  description = "GKE Node Size"
  type        = string
  default     = "e2-highmem-2"
}
