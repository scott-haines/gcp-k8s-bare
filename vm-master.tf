resource "google_compute_instance" "k8s-master" {
    count = "${var.k8s-master-count}"
    name = "k8s-master-vm-${count.index}"
    machine_type = "f1-micro"
    tags = ["k8s-master"]
    metadata = {
        ssh-keys = "${var.ssh_username}:${file("~/.ssh/id_rsa.pub")}"
    }

    boot_disk {
        initialize_params {
            image = "debian-cloud/debian-9"
        }
    }

    network_interface {
        subnetwork = "${google_compute_subnetwork.vpc-subnet.name}"
    }

    connection {
        type = "ssh"
        host = "${google_compute_instance.k8s-master.*.network_interface.0.network_ip}"
        user = "${var.ssh_username}"
        private_key = "${file("${var.ssh-private-key}")}"

        bastion_host = "${google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip}"
        bastion_private_key = "${file("${var.ssh-private-key}")}"
    }

    provisioner "remote-exec" {
        inline = ["echo $HOST"]
    }
}