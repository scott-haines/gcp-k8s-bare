resource "google_compute_network" "vpc" {
  name = "vpc"

  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc-subnet" {
  name          = "vpc-subnet"
  network       = "${google_compute_network.vpc.name}"
  ip_cidr_range = "10.0.0.0/24"
}

resource "google_compute_router" "nat-router" {
  name    = "nat-router"
  network = "${google_compute_network.vpc.self_link}"
  bgp {
    asn = 64514
  }
}

resource "google_compute_address" "nat-external-ip" {
  name = "nat-external-ip"
}

resource "google_compute_router_nat" "nat-cloud" {
  name                               = "nat-cloud"
  router                             = "${google_compute_router.nat-router.name}"
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = ["${google_compute_address.nat-external-ip.self_link}"]
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = "${google_compute_subnetwork.vpc-subnet.self_link}"
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_compute_firewall" "allow-internal" {
  name    = "allow-internal"
  network = "${google_compute_network.vpc.name}"

  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  source_ranges = [
    "${google_compute_subnetwork.vpc-subnet.ip_cidr_range}",
    "${var.k8s-pod-network-cidr}",
    "${var.k8s-service-cluster-ip-cidr}"
  ]
}

resource "google_compute_firewall" "allow-ssh-from-anywhere-to-bastion" {
  name    = "allow-bastion"
  network = "${google_compute_network.vpc.name}"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = ["bastion"]
}
