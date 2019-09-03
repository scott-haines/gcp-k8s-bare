resource "null_resource" "post-bastion-k8s" {
  triggers = {
    master_instance_ids = "${join(",", google_compute_instance.k8s-master.*.id)}"
    worker_instance_ids = "${join(",", google_compute_instance.k8s-worker.*.id)}"
  }

  # Ensure that this resource doesn't execute until after the bastion and all kubernetes servers have been fully
  #   provisioned
  depends_on = [
    "google_compute_instance.bastion",
    "google_compute_instance.k8s-master",
    "google_compute_instance.k8s-worker"
  ]

  # Run all the remote commands on our bastion
  connection {
    type        = "ssh"
    user        = "${var.ssh-username}"
    agent       = "false"
    private_key = "${file("${var.ssh-private-key}")}"
    host        = "${google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${join(",", google_compute_instance.k8s-master.*.id)} > master-instances.txt",
      "echo ${join(",", google_compute_instance.k8s-worker.*.id)} > worker-instances.txt"
    ]
  }
}
