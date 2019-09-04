resource "google_compute_instance_group" "k8s-api-ig" {
  name = "k8s-api-ig"

  instances = "${google_compute_instance.k8s-master.*.self_link}"
}

resource "google_compute_health_check" "k8s-api-hc" {
  name = "k8s-api-hc"

  tcp_health_check {
    port = "6443"
  }
}

resource "google_compute_region_backend_service" "k8s-api-lb" {
  name          = "k8s-api-lb"
  health_checks = ["${google_compute_health_check.k8s-api-hc.self_link}"]

  backend {
    group = "${google_compute_instance_group.k8s-api-ig.self_link}"
  }
}

resource "google_compute_forwarding_rule" "k8s-api-fr" {
  name                  = "k8s-api-fr"
  load_balancing_scheme = "INTERNAL"
  ports                 = ["6443"]
  network               = "${google_compute_network.vpc.self_link}"
  subnetwork            = "${google_compute_subnetwork.vpc-subnet.self_link}"
  backend_service       = "${google_compute_region_backend_service.k8s-api-lb.self_link}"
}
