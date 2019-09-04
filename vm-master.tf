resource "google_compute_instance" "k8s-master" {
  count        = "${var.k8s-master-count}"
  name         = "k8s-master-vm-${count.index}"
  machine_type = "f1-micro"
  tags         = ["k8s-master"]
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
  }
}
