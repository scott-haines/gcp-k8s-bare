resource "google_compute_instance" "k8s-worker" {
  count          = "${var.k8s-worker-count}"
  name           = "k8s-worker-vm-${count.index}"
  machine_type   = "f1-micro"
  can_ip_forward = "true"
  tags           = ["k8s-worker"]

  depends_on = [
    "google_compute_router_nat.nat-cloud"
  ]

  metadata = {
    ssh-keys = "${var.ssh-username}:${file("~/.ssh/id_rsa.pub")}"
    pod-cidr = "${cidrsubnet(var.k8s-pod-network-cidr, var.k8s-worker-count - 1, count.index)}"
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-1804-lts"
    }
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.vpc-subnet.name}"
  }

  connection {
    type        = "ssh"
    user        = "${var.ssh-username}"
    agent       = "false"
    private_key = "${file("${var.ssh-private-key}")}"
    host        = "${element(google_compute_instance.k8s-worker.*.network_interface.0.network_ip, count.index)}"

    bastion_host        = "${google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip}"
    bastion_private_key = "${file("${var.ssh-private-key}")}"
  }

  provisioner "file" {
    source      = "service-templates/docker.socket"
    destination = "docker.socket"
  }

  provisioner "file" {
    source      = "service-templates/docker.service"
    destination = "docker.service"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo modprobe br_netfilter", # AAAAAHHHHH :( https://ebtables.netfilter.org/documentation/bridge-nf.html
      "curl https://download.docker.com/linux/static/stable/x86_64/docker-18.09.6.tgz -o docker-18.09.6.tgz",
      "tar xzvf docker-18.09.6.tgz",
      "sudo cp docker/* /usr/bin/",
      "sudo mv docker.service /etc/systemd/system/docker.service",
      "sudo mv docker.socket /etc/systemd/system/docker.socket",
      "sudo systemctl daemon-reload",
      "sudo cp docker/docker /usr/local/bin/",
      "sudo groupadd -g 10000 docker",
      "sudo systemctl enable docker",
      "sudo systemctl start docker"
    ]
  }
}
