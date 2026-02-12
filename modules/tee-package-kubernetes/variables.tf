variable "deploy_suffix" {
  description = "Deployment suffix, used to prefix resource names in case of testing multiple deploys at the same time"
  default     = ""
}

variable "service_account_email" {
  description = "Email of service account with proper permissions to pull images from repo etc..."
}

variable "tee_docker_image" {
  description = "Docker image used for tee-machine."
}

variable "tee_proxy_docker_image" {
  description = "Docker image used for tee-proxy."
  default     = "europe-west1-docker.pkg.dev/flare-network-staging/containers/tee-proxy:0.0.8"
}

variable "is_extension" {
  description = "Set to true if this package will deploy an extension"
  default     = false
}

variable "initial_owner" {
  description = "Initial owner address for TEE node."
  default     = "0xEfFDC9d60eaa243b2fCC5c2A21FA938B3A872d07"
}

variable "extension_id" {
  description = "Extension ID to be used by the TEE machine."
  default     = "0x0000000000000000000000000000000000000000000000000000000000000000"
}


variable "region" {
  description = "Deployment region"
  default     = "europe-west1"
}

variable "zone" {
  description = "Deployment zone"
  default     = "europe-west1-b"
}

variable "tee_machine_type" {
  description = "Machine type for tee-machine."
  default     = "c3d-standard-4"
}

variable "tee_indexer_database" {
  description = "Configuration for the TEE Indexer database"
  type = object({
    hostname     = string
    port         = number
    databaseName = string
    user         = string
    password     = string
  })
  sensitive = true
}

variable "deploy_account_email" {
  description = "email of account used for deploys. module will add permissions that are needed to perform the deploy (for tee-node and tee-proxy)"
}

variable "namespace" {
  description = "Kubernetes namespace where to deploy the resources"
  default     = "tee"
}

variable "project" {
  description = "GCP project where resources will be created"
  default     = "flare-network-staging"
}

variable "tee_machine_debug_mode" {
  description = "Debug mode for tee machine"
  type        = bool
  default     = false
}

variable "network" {
  description = "VPC network self link to use for all resources"
  type        = string
}
