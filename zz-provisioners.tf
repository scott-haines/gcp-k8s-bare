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

      for master in ${join(" ", google_compute_instance.k8s-master.*.id)}; do
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          ~/etcd-v3.4.0-linux-amd64.tar.gz $${master}:~/
      done

      for master in ${join(" ", google_compute_instance.k8s-master.*.id)}; do
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          ~/kube-apiserver ~/kube-controller-manager ~/kube-scheduler \
          /usr/local/bin/kubectl $${master}:~/
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

  connection {
    type        = "ssh"
    user        = "${var.ssh-username}"
    agent       = "false"
    private_key = "${file("${var.ssh-private-key}")}"
    host        = "${element(google_compute_instance.k8s-master.*.network_interface.0.network_ip, count.index)}"

    bastion_host        = "${google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip}"
    bastion_private_key = "${file("${var.ssh-private-key}")}"
  }

  provisioner "file" {
    source      = "service-templates/etcd-template.service"
    destination = "etcd-template.service"
  }

  # This needs to be executed on each of the masters
  provisioner "remote-exec" {
    # Note the indentation of the EOT - Terraform is picky about the EOTs
    inline = [<<EOT
      tar -xvf etcd-v3.4.0-linux-amd64.tar.gz
      sudo mv etcd-v3.4.0-linux-amd64/etcd* /usr/local/bin/
      sudo mkdir -p /etc/etcd /var/lib/etcd
      sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/

      export INTERNAL_IP=${element(google_compute_instance.k8s-master.*.network_interface.0.network_ip, count.index)}
      export ETCD_NAME=$(hostname -s)
      echo "${join("\n", google_compute_instance.k8s-master.*.id)}" > master_names.txt
      echo "${join("\n", google_compute_instance.k8s-master.*.network_interface.0.network_ip)}" > master_ips.txt
      export INITIAL_CLUSTER=$(paste master_names.txt master_ips.txt | awk -F '\t' '{ print $1 "=https://" $2 ":2380"; line="" }' | paste -sd "," -)
      envsubst < etcd-template.service > etcd.service
      sudo mv etcd.service /etc/systemd/system/etcd.service
      sudo systemctl daemon-reload
      sudo systemctl enable etcd
      sudo systemctl start etcd
    EOT
    ]
  }
}

resource "null_resource" "bootstrap-k8s-control-plane" {
  count = "${var.k8s-master-count}"
  depends_on = [
    "null_resource.bootstrap-etcd-on-k8s-masters"
  ]

  connection {
    type        = "ssh"
    user        = "${var.ssh-username}"
    agent       = "false"
    private_key = "${file("${var.ssh-private-key}")}"
    host        = "${element(google_compute_instance.k8s-master.*.network_interface.0.network_ip, count.index)}"

    bastion_host        = "${google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip}"
    bastion_private_key = "${file("${var.ssh-private-key}")}"
  }

  provisioner "file" {
    source      = "service-templates/kube-apiserver-template.service"
    destination = "kube-apiserver-template.service"
  }

  # This needs to be executed on each of the masters
  provisioner "remote-exec" {
    # Note the indentation of the EOT - Terraform is picky about the EOTs
    inline = [<<EOT
      chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
      sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/

      sudo mkdir -p /var/lib/kubernetes/

      sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
        service-account-key.pem service-account.pem \
        encryption-config.yaml /var/lib/kubernetes/

      export INTERNAL_IP=${element(google_compute_instance.k8s-master.*.network_interface.0.network_ip, count.index)}
      export ETCD_SERVERS=$(echo "${join("\n", google_compute_instance.k8s-master.*.network_interface.0.network_ip)}" | awk -F '\n' '{ print "https://" $1 ":2379"; line="" }' | paste -sd "," -)
      export SERVICE_CLUSTER_CIDR=${var.k8s-service-cluster-ip-cidr}
      export API_SERVER_COUNT=${var.k8s-master-count}
      envsubst < kube-apiserver-template.service > kube-apiserver.service
      sudo mv kube-apiserver.service /etc/systemd/system/kube-apiserver.service
    EOT
    ]
  }

  provisioner "file" {
    source      = "service-templates/kube-controller-manager-template.service"
    destination = "kube-controller-manager-template.service"
  }

  provisioner "remote-exec" {
    # Note the indentation of the EOT - Terraform is picky about the EOTs
    inline = [<<EOT
      sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/

      export K8S_POD_NETWORK_CIDR=${var.k8s-pod-network-cidr}
      export SERVICE_CLUSTER_CIDR=${var.k8s-service-cluster-ip-cidr}
      envsubst < kube-controller-manager-template.service > kube-controller-manager.service
      sudo mv kube-controller-manager.service /etc/systemd/system/kube-controller-manager.service
    EOT
    ]
  }

  provisioner "file" {
    source      = "service-templates/kube-scheduler.yaml"
    destination = "kube-scheduler.yaml"
  }
  provisioner "file" {
    source      = "service-templates/kube-scheduler.service"
    destination = "kube-scheduler.service"
  }

  provisioner "remote-exec" {
    # Note the indentation of the EOT - Terraform is picky about the EOTs
    inline = [<<EOT
      sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/

      sudo mkdir -p /etc/kubernetes/config/
      sudo mv kube-scheduler.yaml /etc/kubernetes/config/kube-scheduler.yaml
      sudo mv kube-scheduler.service /etc/systemd/system/kube-scheduler.service
    EOT
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl daemon-reload",
      "sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler",
      "sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler"
    ]
  }
}

resource "null_resource" "install-nginx-for-healthchecks" {
  count = "${var.k8s-master-count}"
  depends_on = [
    "null_resource.bootstrap-k8s-control-plane"
  ]

  connection {
    type        = "ssh"
    user        = "${var.ssh-username}"
    agent       = "false"
    private_key = "${file("${var.ssh-private-key}")}"
    host        = "${element(google_compute_instance.k8s-master.*.network_interface.0.network_ip, count.index)}"

    bastion_host        = "${google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip}"
    bastion_private_key = "${file("${var.ssh-private-key}")}"
  }

  provisioner "file" {
    source      = "service-templates/kubernetes.default.svc.cluster.local"
    destination = "kubernetes.default.svc.cluster.local"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install -y nginx",
      "sudo mv kubernetes.default.svc.cluster.local /etc/nginx/sites-available/kubernetes.default.svc.cluster.local",
      "sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/",
      "sudo systemctl restart nginx",
      "sudo systemctl enable nginx"
    ]
  }
}

resource "null_resource" "configure-kube-apiserver-rbac" {
  depends_on = [
    "null_resource.install-nginx-for-healthchecks"
  ]

  connection {
    type        = "ssh"
    user        = "${var.ssh-username}"
    agent       = "false"
    private_key = "${file("${var.ssh-private-key}")}"

    # Only execute this on the first master (index 0)
    host = "${element(google_compute_instance.k8s-master.*.network_interface.0.network_ip, 0)}"

    bastion_host        = "${google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip}"
    bastion_private_key = "${file("${var.ssh-private-key}")}"
  }

  provisioner "file" {
    source      = "service-templates/kubeapi-cluster-role.yaml"
    destination = "kubeapi-cluster-role.yaml"
  }

  provisioner "file" {
    source      = "service-templates/kubeapi-cluster-role-binding.yaml"
    destination = "kubeapi-cluster-role-binding.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "kubectl apply --kubeconfig admin.kubeconfig -f kubeapi-cluster-role.yaml",
      "kubectl apply --kubeconfig admin.kubeconfig -f kubeapi-cluster-role-binding.yaml"
    ]
  }
}
