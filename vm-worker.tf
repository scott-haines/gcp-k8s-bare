resource "google_compute_instance" "k8s-worker" {
  count        = "${var.k8s-worker-count}"
  name         = "k8s-worker-vm-${count.index}"
  machine_type = "f1-micro"
  tags         = ["k8s-worker"]
  metadata = {
    ssh-keys = "${var.ssh-username}:${file("~/.ssh/id_rsa.pub")}"
    pod-cidr = "${cidrsubnet(var.k8s-pod-network-cidr, var.k8s-worker-count, count.index)}"
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
