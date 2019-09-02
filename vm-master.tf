resource "google_compute_instance" "master" {
    name = "master-vm"
    machine_type = "f1-micro"

    boot_disk {
        initialize_params {
            image = "debian-cloud/debian-9"
        }
    }

    network_interface {
        subnetwork = "${google_compute_subnetwork.management-subnet.name}"
    }
}