terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }

    helm = {
      source = "hashicorp/helm"
    }

    cloudflare = {
      source = "cloudflare/cloudflare"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}
