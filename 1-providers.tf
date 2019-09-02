provider "google" {
    credentials = "${file("secrets/service-account-credentials.json")}"
    project = "lfd259-shaines"
    region = "us-east1"
    zone = "us-east1-b"
}