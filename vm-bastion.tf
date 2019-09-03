resource "google_compute_instance" "bastion" {
    name            = "bastion-vm"
    machine_type    = "f1-micro"
    tags            = ["bastion"]
    
    metadata = {
        ssh-keys = "${var.ssh-username}:${file("~/.ssh/id_rsa.pub")}"
    }

    boot_disk {
        initialize_params {
            image = "debian-cloud/debian-9"
        }
    }

    network_interface {
        subnetwork = "${google_compute_subnetwork.vpc-subnet.name}"

        access_config {
            // this section is included to give external IP
        }
    }

    provisioner "local-exec" {
        command = "curl -X POST 'https://${var.dns-k8s-bastionuser-name}:${var.dns-k8s-bastion-password}@domains.google.com/nic/update?hostname=${var.k8s-bastion-fqdn}&myip=${google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip}&offline=no'"
    }

    provisioner "local-exec" {
        when = "destroy"
        command = "curl -X POST 'https://${var.dns-k8s-bastionuser-name}:${var.dns-k8s-bastion-password}@domains.google.com/nic/update?hostname=${var.k8s-bastion-fqdn}&offline=yes'"
        on_failure = "continue"
    }
}