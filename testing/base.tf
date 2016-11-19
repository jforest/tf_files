variable "creds" {
  description = "Path to the JSON file used to describe your account credentials"
}
variable "project" {}
variable "region" {
  default = "us-east1"
}

provider "google" {
  credentials = "${file(var.creds)}"
  project     = "${var.project}"
  region      = "${var.region}"
}

resource "google_compute_network" "test" {
  name       = "test"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "fe" {
  name          = "test-subnet1"
  ip_cidr_range = "10.1.0.0/24"
  network       = "${google_compute_network.test.self_link}"
  region        = "us-east1"
}

resource "google_compute_subnetwork" "www" {
  name          = "test-subnet2"
  ip_cidr_range = "10.2.0.0/24"
  network       = "${google_compute_network.test.self_link}"
  region        = "us-east1"
}

resource "google_compute_address" "fe" {
  name = "test-bastion-address"
}

resource "google_compute_address" "www" {
  name = "test-www-address"
}

resource "google_compute_firewall" "test-ssh" {
  name    = "test-ssh"
  network = "${google_compute_network.test.name}"
  description = "Allow in ssh from joshes home"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["67.253.78.49/32"]
  target_tags = ["bastion"]
}

resource "google_compute_firewall" "www" {
  name    = "test-www-firewall"
  network = "${google_compute_network.test.name}"
  description = "Allow in web traffic from anywhere to www-node"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags = ["www-node"]
}

resource "google_compute_firewall" "internal" {
  name = "test-internal-ssh"
  network = "${google_compute_network.test.name}"
  description = "Allow ssh from bastion -> backend hosts"

  allow {
    protocol = "tcp"
    ports = ["22"]
  }

  source_tags = ["bastion"]
  target_tags = ["backend"]
}

resource "google_compute_instance" "test-bastion" {
  name         = "test-bastion"
  machine_type = "n1-standard-1"
  zone         = "us-east1-d"

  tags = ["bastion"]

  disk {
    image = "ubuntu-os-cloud/ubuntu-1604-lts"
    size = 50
  }

  network_interface {
    subnetwork = "test-subnet1"
    access_config {
      nat_ip = "${google_compute_address.fe.address}"
    }
  }

  metadata {
    hostname = "test.foresj.net"
  }

  metadata_startup_script = "echo hi > /test.txt"

  scheduling {
    on_host_maintenance = "MIGRATE"
    automatic_restart = "true"
  }

  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }
}





output "public_ip" {
  value = "${google_compute_address.www.address}"
}
