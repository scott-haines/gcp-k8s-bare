terraform {
    backend "gcs" {
        credentials="secrets/service-account-credentials.json"
        bucket = "${var.backend-bucket-name}"
        prefix = "terraform/state"
    }
}