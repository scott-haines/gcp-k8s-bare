resource "google_compute_firewall" "allow-ingress-to-k8s-api-lb" {
  name    = "allow-ingress-to-k8s-api-lb"
  network = "${google_compute_network.vpc.name}"

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

resource "google_compute_http_health_check" "k8s-api-hc" {
  name         = "k8s-api-hc"
  request_path = "/healthz"
  host         = "kubernetes.default.svc.cluster.local"
}

resource "google_compute_target_pool" "k8s-api-target-pool" {
  name = "k8s-api-target-pool"

  instances = "${google_compute_instance.k8s-master.*.self_link}"

  health_checks = [
    "${google_compute_http_health_check.k8s-api-hc.self_link}",
  ]
}

resource "google_compute_forwarding_rule" "k8s-api-forwarding-rule" {
  name       = "k8s-api-forwarding-rule"
  target     = "${google_compute_target_pool.k8s-api-target-pool.self_link}"
  port_range = "6443"
}
