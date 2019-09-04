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

  provisioner "file" {
    source      = "certificate-templates"
    destination = "certificate-configs"
  }

  provisioner "remote-exec" {
    # Note the indentation of the EOT - Terraform is picky about the EOTs
    inline = [<<EOT
      cd certificate-configs
      KUBERNETES_ILB_ADDRESS=${google_compute_forwarding_rule.k8s-api-fr.ip_address}
      
      for worker in ${join(" ", google_compute_instance.k8s-worker.*.id)}; do
        cp certificate-templates/worker-template.json certificate-templates/$${worker}-csr.json
        WORKER_NODE=$${worker} envsubst < certificate-templates/$${worker}-csr.json > $${worker}-csr.json

        cfssl gencert \
          -ca=ca.pem \
          -ca-key=ca-key.pem \
          -config=ca-config.json \
          -hostname=$${worker} \
          -profile=kubernetes \
          $${worker}-csr.json | cfssljson -bare $${worker}


        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          ca.pem $${worker}-key.pem $${worker}.pem $${worker}:~/
      
        kubectl config set-cluster gcp-kubernetes \
          --certificate-authority=ca.pem \
          --embed-certs=true \
          --server=https://$${KUBERNETES_ILB_ADDRESS}:6443 \
          --kubeconfig=$${worker}.kubeconfig

        kubectl config set-credentials system:node:$${worker} \
          --client-certificate=$${worker}.pem \
          --client-key=$${worker}-key.pem \
          --embed-certs=true \
          --kubeconfig=$${worker}.kubeconfig

        kubectl config set-context default \
          --cluster=gcp-kubernetes \
          --user=system:node:$${worker} \
          --kubeconfig=$${worker}.kubeconfig

        kubectl config use-context default --kubeconfig=$${worker}.kubeconfig
      done

      for master in ${join(" ", google_compute_instance.k8s-master.*.id)}; do
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
          service-account-key.pem service-account.pem $${master}:~/
      done
    EOT
    ]
  }
}
