# Variables
variable "creds" {
  description = "Path to the JSON file used to describe your account credentials"
}
variable "project" {}
variable "region" {
  default = "us-east1"
}
variable "ssh_user" {
  default = "admin"
}
variable "ssh_key" {
  default = "~/.ssh/id_rsa.pub"
}



# Google creds
provider "google" {
  credentials = "${file(var.creds)}"
  project     = "${var.project}"
  region      = "${var.region}"
}



# Network and subnet configs here
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



# Static IPs here
resource "google_compute_address" "bastion" {
  name = "test-bastion-address"
}

resource "google_compute_address" "www" {
  name = "test-www-address"
}



# Firewall rules here
resource "google_compute_firewall" "bastion-ssh" {
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



# Load balancer below this
resource "google_compute_target_pool" "www" {
  name = "test-www-target-pool"
  instances = ["${google_compute_instance.www.*.self_link}"]
  health_checks = ["${google_compute_http_health_check.http.name}"]
}

resource "google_compute_forwarding_rule" "http" {
  name = "test-www-http-forwarding-rule"
  target = "${google_compute_target_pool.www.self_link}"
  ip_address = "${google_compute_address.www.address}"
  port_range = "80-80"
}

resource "google_compute_forwarding_rule" "https" {
  name = "test-www-https-forwarding-rule"
  target = "${google_compute_target_pool.www.self_link}"
  ip_address = "${google_compute_address.www.address}"
  port_range = "443-443"
}

resource "google_compute_http_health_check" "http" {
  name = "test-www-http-basic-check"
  request_path = "/"
  check_interval_sec = 1
  healthy_threshold = 1
  unhealthy_threshold = 10
  timeout_sec = 1
}



# Instances go here
resource "google_compute_instance" "test-bastion" {
  name         = "test-bastion"
  machine_type = "f1-micro"
  zone         = "us-east1-d"
  depends_on = ["google_compute_subnetwork.fe"]

  tags = ["bastion"]

  disk {
    image = "debian-cloud/debian-8"
  }

  network_interface {
    subnetwork = "test-subnet1"
    access_config {
      nat_ip = "${google_compute_address.bastion.address}"
    }
  }

  metadata {
    hostname = "test.foresj.net"
    sshKeys = "${var.ssh_user}:${file(var.ssh_key)}"
  }

  scheduling {
    on_host_maintenance = "MIGRATE"
    automatic_restart = "true"
  }

  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }
}

resource "google_compute_instance" "www" {
  count = 2
  name = "test-www-${count.index}"
  machine_type = "f1-micro"
  zone = "us-east1-d"
  depends_on = ["google_compute_subnetwork.www"]

  tags = ["www-node","backend"]

  disk {
    image = "debian-cloud/debian-8"
  }

  network_interface {
    subnetwork = "test-subnet2"
    access_config {
        # Ephemeral
    }
  }

  scheduling {
    on_host_maintenance = "MIGRATE"
    automatic_restart = "true"
  }

  service_account {
    scopes = ["compute-ro"]
  }

  metadata_startup_script = <<SCRIPT
aptitude -y update
#aptitude -y safe-upgrade
aptitude install -y nginx
service nginx start
SCRIPT

  metadata {
    hostname = "www${count.index}.foresj.net"
    sshKeys = "${var.ssh_user}:${file(var.ssh_key)}"
  }
}



output "www_public_ip" {
  value = "${google_compute_address.www.address}"
}
output "bastion_public_ip" {
  value = "${google_compute_address.bastion.address}"
}
output "www_output" {
  value = "${google_compute_instance.www.network_interface.0.address}"
}
