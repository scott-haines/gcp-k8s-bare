# Instance group for jumpbox not currently used.

resource "google_compute_instance_group" "ig-jumpbox" {
    name = "ig-jumpbox"

    network = "${google_compute_network.external-network.self_link}"

    instances = [
        "${google_compute_instance.jumpbox.self_link}"
    ]

    named_port {
        name = "ssh"
        port = "22"
    }
}