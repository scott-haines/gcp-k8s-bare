resource "google_compute_network" "external-network" {
    name = "external-network"

    auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "external-subnet" {
    name = "external-subnet"
    network = "${google_compute_network.external-network.name}"
    ip_cidr_range = "10.99.99.0/24"
}

resource "google_compute_firewall" "external" {
    name = "external"
    network = "${google_compute_network.external-network.name}"

    allow {
        protocol = "icmp"
    }

    allow {
        protocol = "tcp"
        ports = ["22"]
    }
}