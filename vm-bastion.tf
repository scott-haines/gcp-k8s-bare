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
    source      = "certificate-configs"
    destination = "certificate-configs"
  }

  provisioner "remote-exec" {
    # Note the indentation of the EOT - Terraform is picky about the EOTs :(
    # On the plus side this allows us to do the following with nested EOFs :)
    inline = [<<EOT
    cd certificate-configs
    
    cfssl gencert -initca ca-csr.json | cfssljson -bare ca
    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      admin-csr.json | cfssljson -bare admin
    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      kube-proxy-csr.json | cfssljson -bare kube-proxy
    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      kube-scheduler-csr.json | cfssljson -bare kube-scheduler
    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -hostname=${join(",", google_compute_instance.k8s-master.*.network_interface.0.network_ip)},127.0.0.1,kubernetes.default \
      -profile=kubernetes \
      kubernetes-csr.json | cfssljson -bare kubernetes
    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      service-account-csr.json | cfssljson -bare service-account
    EOT
    ]
  }

  # ** NOTE ** - An existing bug in terraform prevents a tainted resource from executing provisioners
  #  with the 'when = "destroy"' attribute.  See https://github.com/hashicorp/terraform/issues/13549
  # This bug manifests itself primarily when tainting a resource then executing terraform destroy
  #  without first untainting the resource.  The behaviour is expected for the workflow 
  #  "taint resource => terraform apply" to re-create a resource. 
  provisioner "local-exec" {
    when       = "destroy"
    command    = "curl -X POST 'https://${var.dns-k8s-bastion-username}:${var.dns-k8s-bastion-password}@domains.google.com/nic/update?hostname=${var.k8s-bastion-fqdn}&offline=yes'"
    on_failure = "continue"
  }
}
