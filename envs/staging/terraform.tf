terraform {
  required_version = ">1.11.0"

  backend "gcs" {
    bucket = "flare-tf-flare-staging-state-store"
    prefix = "17811669-infra/tee_package/staging_k8s"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~>6.6.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.3"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.26.0"
    }

  }
}
