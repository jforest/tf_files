variable "ssh_user" {
  default = "admin"
}
variable "ssh_pub_key_path" {}

provider "google" {
  credentials = "${file("/Users/jforest/.secure/creds.json")}"
  project     = "learning-149919"
  region      = "us-east1"
}

resource "google_compute_network" "lucca" {
  name       = "lucca"
}

resource "google_compute_subnetwork" "lucca1" {
  name          = "lucca1"
  ip_cidr_range = "10.220.0.0/24"
  network       = "${google_compute_network.lucca.self_link}"
  region        = "us-east1"
}

resource "google_compute_address" "lucca-address" {
  name = "lucca-address"
}

resource "google_compute_firewall" "lucca-ssh" {
  name    = "lucca-ssh"
  network = "${google_compute_network.lucca.name}"
  description = "Allow in ssh from joshes home"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["67.253.78.49/32"]
}

resource "google_compute_firewall" "lucca-web" {
  name    = "lucca-web"
  network = "${google_compute_network.lucca.name}"
  description = "Allow in web traffic from anywhere"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "lucca" {
  name         = "lucca"
  machine_type = "n1-standard-1"
  zone         = "us-east1-d"
  depends_on   = ["google_compute_subnetwork.lucca1"]

  tags = ["lucca", "personal"]

  disk {
    image = "debian-cloud/debian-8"
    type = "pd-ssd"
    size = 50
  }

  network_interface {
    subnetwork = "lucca1"
    access_config {
      nat_ip = "${google_compute_address.lucca-address.address}"
    }
  }

  metadata {
    hostname = "lucca.foresj.net"
    sshKeys = "${var.ssh_user}:${file(var.ssh_pub_key_path)}"
  }

  scheduling {
    on_host_maintenance = "MIGRATE"
    automatic_restart = "true"
  }

  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }
}
