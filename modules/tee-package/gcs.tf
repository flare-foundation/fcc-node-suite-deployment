resource "google_storage_bucket" "tee_proxy" {
  name                        = join("-", compact([var.project, "tee-proxy", var.deploy_suffix]))
  project                     = var.project
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }
}

# The tee-proxy VM already runs as var.service_account_email (see proxy-server.tf),
# so it can read/write the bucket directly without a separate identity or
# workload-identity binding, unlike upstream's Kubernetes-based deployment.
resource "google_storage_bucket_iam_member" "tee_proxy" {
  bucket = google_storage_bucket.tee_proxy.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${var.service_account_email}"
}
