resource "google_compute_instance" "bastion" {
  name         = "bastion-vm"
  machine_type = "f1-micro"
  tags         = ["bastion"]

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

  connection {
    type        = "ssh"
    user        = "${var.ssh-username}"
    agent       = "false"
    private_key = "${file("${var.ssh-private-key}")}"
    host        = "${google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip}"
  }

  provisioner "local-exec" {
    command = "curl -X POST 'https://${var.dns-k8s-bastion-username}:${var.dns-k8s-bastion-password}@domains.google.com/nic/update?hostname=${var.k8s-bastion-fqdn}&myip=${google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip}&offline=no'"
  }

  provisioner "remote-exec" {
    # Configure the bastion to be able to execute cfssl and kubectl commands.
    inline = [
      "sudo apt update",
      "sudo apt upgrade -y",
      "sudo curl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -o /usr/local/bin/cfssl",
      "sudo curl https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -o /usr/local/bin/cfssljson",
      "sudo curl https://storage.googleapis.com/kubernetes-release/release/v1.12.0/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl",
      "sudo chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson /usr/local/bin/kubectl"
    ]
  }

  provisioner "file" {
    source       = "certificate-configs"
    destrination = "certificate-configs"
  }

  provisioner "local-exec" {
    when       = "destroy"
    command    = "curl -X POST 'https://${var.dns-k8s-bastion-username}:${var.dns-k8s-bastion-password}@domains.google.com/nic/update?hostname=${var.k8s-bastion-fqdn}&offline=yes'"
    on_failure = "continue"
  }
}
