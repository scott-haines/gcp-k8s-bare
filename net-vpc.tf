resource "google_compute_network" "vpc" {
    name = "vpc"

    auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc-subnet" {
    name = "vpc-subnet"
    network = "${google_compute_network.vpc.name}"
    ip_cidr_range = "10.0.0.0/24"
}

resource "google_compute_firewall" "allow-internal" {
    name = "allow-internal"
    network = "${google_compute_network.vpc.name}"

    allow {
        protocol = "icmp"
    }
    allow {
        protocol = "tcp"
        ports = ["0-65535"]
    }

    source_ranges = ["${google_compute_subnetwork.vpc-subnet.ip_cidr_range}"]
}

resource "google_compute_firewall" "allow-jumpbox" {
    name = "allow-jumpbox"
    network = "${google_compute_network.vpc.name}"

    allow {
        protocol = "icmp"
    }
    allow {
        protocol = "tcp"
        ports = ["22"]
    }

    target_tags = ["jumpbox"]
}