resource "google_compute_network" "management-network" {
    name = "management-network"

    auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "management-subnet" {
    name = "management-subnet"
    network = "${google_compute_network.management-network.name}"
    ip_cidr_range = "10.0.0.0/24"
}

resource "google_compute_firewall" "management" {
    name = "management"
    network = "${google_compute_network.management-network.name}"

    allow {
        protocol = "icmp"
    }
}