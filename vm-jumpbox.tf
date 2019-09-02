resource "google_compute_instance" "jumpbox" {
    name = "jumpbox-vm"
    machine_type = "f1-micro"
    metadata = {
        ssh-keys = "${var.ssh_username}:${file("~/.ssh/id_rsa.pub")}"
    }

    boot_disk {
        initialize_params {
            image = "debian-cloud/debian-9"
        }
    }

    network_interface {
        subnetwork = "${google_compute_subnetwork.external-subnet.name}"

        access_config {
            // this section is included to give external IP
        }
    }

    network_interface {
        subnetwork = "${google_compute_subnetwork.management-subnet.name}"
    }

    provisioner "local-exec" {
        command = "curl -X POST 'https://${var.dns_k8s-jumpbox_username}:${var.dns_k8s-jumpbox_password}@domains.google.com/nic/update?hostname=${var.k8s-jumpbox_fqdn}&myip=${google_compute_instance.jumpbox.network_interface.0.access_config.0.nat_ip}&offline=no'"
    }

    provisioner "local-exec" {
        when = "destroy"
        command = "curl -X POST 'https://${var.dns_k8s-jumpbox_username}:${var.dns_k8s-jumpbox_password}@domains.google.com/nic/update?hostname=${var.k8s-jumpbox_fqdn}&offline=yes'"
        on_failure = "continue"
    }
}