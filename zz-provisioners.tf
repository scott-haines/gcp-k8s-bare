resource "null_resource" "generate-certs-kubeconfigs-and-distribute" {
  # Ensure that this resource doesn't execute until after the bastion and all kubernetes 
  #  servers have been fully provisioned
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

  provisioner "file" {
    source      = "data-encryption"
    destination = "data-encryption"
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
      done

      for master in ${join(" ", google_compute_instance.k8s-master.*.id)}; do
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
          service-account-key.pem service-account.pem $${master}:~/
      done

      # Kubelet Kubernetes Configuration Files (Workers)
      for worker in ${join(" ", google_compute_instance.k8s-worker.*.id)}; do
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

      # kube-proxy
      kubectl config set-cluster gcp-kubernetes \
        --certificate-authority=ca.pem \
        --embed-certs=true \
        --server=https://$${KUBERNETES_ILB_ADDRESS}:6443 \
        --kubeconfig=kube-proxy.kubeconfig

      kubectl config set-credentials system:kube-proxy \
        --client-certificate=kube-proxy.pem \
        --client-key=kube-proxy-key.pem \
        --embed-certs=true \
        --kubeconfig=kube-proxy.kubeconfig

      kubectl config set-context default \
        --cluster=gcp-kubernetes \
        --user=system:kube-proxy \
        --kubeconfig=kube-proxy.kubeconfig

      kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

      # kube-controller-manager
      kubectl config set-cluster gcp-kubernetes \
        --certificate-authority=ca.pem \
        --embed-certs=true \
        --server=https://127.0.0.1:6443 \
        --kubeconfig=kube-controller-manager.kubeconfig

      kubectl config set-credentials system:kube-controller-manager \
        --client-certificate=kube-controller-manager.pem \
        --client-key=kube-controller-manager-key.pem \
        --embed-certs=true \
        --kubeconfig=kube-controller-manager.kubeconfig

      kubectl config set-context default \
        --cluster=gcp-kubernetes \
        --user=system:kube-controller-manager \
        --kubeconfig=kube-controller-manager.kubeconfig

      kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig

      # kube-scheduler
      kubectl config set-cluster gcp-kubernetes \
        --certificate-authority=ca.pem \
        --embed-certs=true \
        --server=https://127.0.0.1:6443 \
        --kubeconfig=kube-scheduler.kubeconfig

      kubectl config set-credentials system:kube-scheduler \
        --client-certificate=kube-scheduler.pem \
        --client-key=kube-scheduler-key.pem \
        --embed-certs=true \
        --kubeconfig=kube-scheduler.kubeconfig

      kubectl config set-context default \
        --cluster=gcp-kubernetes \
        --user=system:kube-scheduler \
        --kubeconfig=kube-scheduler.kubeconfig

      kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig

      # admin
      kubectl config set-cluster gcp-kubernetes \
        --certificate-authority=ca.pem \
        --embed-certs=true \
        --server=https://127.0.0.1:6443 \
        --kubeconfig=admin.kubeconfig

      kubectl config set-credentials admin \
        --client-certificate=admin.pem \
        --client-key=admin-key.pem \
        --embed-certs=true \
        --kubeconfig=admin.kubeconfig

      kubectl config set-context default \
        --cluster=gcp-kubernetes \
        --user=admin \
        --kubeconfig=admin.kubeconfig

      kubectl config use-context default --kubeconfig=admin.kubeconfig

      for worker in ${join(" ", google_compute_instance.k8s-worker.*.id)}; do
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          $${worker}.kubeconfig kube-proxy.kubeconfig $${worker}:~/
      done
      for master in ${join(" ", google_compute_instance.k8s-master.*.id)}; do
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          admin.kubeconfig kube-controller-manager.kubeconfig \
          kube-scheduler.kubeconfig $${master}:~/
      done

      cd ~/data-encryption
      ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64) \
        envsubst < encryption-config-template.yaml > encryption-config.yaml

      for master in ${join(" ", google_compute_instance.k8s-master.*.id)}; do
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          encryption-config.yaml $${master}:~/
      done
    EOT
    ]
  }
}

resource "null_resource" "bootstrap-etcd-on-k8s-masters" {
  count = "${var.k8s-master-count}"
  depends_on = [
    "null_resource.generate-certs-kubeconfigs-and-distribute"
  ]

  # This needs to be executed on each of the masters
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "${var.ssh-username}"
      agent       = "false"
      private_key = "${file("${var.ssh-private-key}")}"
      host        = "${element(google_compute_instance.k8s-master.*.network_interface.0.network_ip, count.index)}"

      bastion_host        = "${google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip}"
      bastion_private_key = "${file("${var.ssh-private-key}")}"
    }

    # Note the indentation of the EOT - Terraform is picky about the EOTs
    inline = [<<EOT
      # Download the etcd binaries and upload to managers
      curl -L https://github.com/etcd-io/etcd/releases/download/v3.4.0/etcd-v3.4.0-linux-amd64.tar.gz -o etcd-v3.4.0-linux-amd64.tar.gz
      tar -xvf etcd-v3.4.0-linux-amd64.tar.gz
      sudo mkdir -p /etc/etcd /var/lib/etcd
      sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/

      export INTERNAL_IP=${element(google_compute_instance.k8s-master.*.network_interface.0.network_ip, count.index)}
      export ETCD_NAME=$(hostname -s)
      echo "${join(",", google_compute_instance.k8s-master.*.id)}|${join(",", google_compute_instance.k8s-master.*.network_interface.0.network_ip)}" > master_zipmap.txt
    EOT
    ]
  }
}
