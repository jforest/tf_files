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
resource "google_compute_network" "lbtest" {
  name       = "lbtest"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "fe" {
  name          = "lbtest-subnet1"
  ip_cidr_range = "10.1.0.0/24"
  network       = "${google_compute_network.lbtest.self_link}"
  region        = "us-east1"
}

resource "google_compute_subnetwork" "www" {
  name          = "lbtest-subnet2"
  ip_cidr_range = "10.2.0.0/24"
  network       = "${google_compute_network.lbtest.self_link}"
  region        = "us-east1"
}



# Static IPs here
resource "google_compute_address" "www" {
  name = "lbtest-www-address"
}



# Firewall rules here
resource "google_compute_firewall" "lbtest-ssh" {
  name    = "lbtest-ssh"
  network = "${google_compute_network.lbtest.name}"
  description = "Allow in ssh from joshes home"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["67.253.78.49/32"]
  target_tags = ["www-node"]
}

resource "google_compute_firewall" "mainip" {
  name = "mainip"
  network = "${google_compute_network.lbtest.name}"
  description = "Allow http/https in from everywhere"

  allow {
    protocol = "tcp"
    ports = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
}



# Load balancer below this
resource "google_compute_target_pool" "www" {
  name = "lbtest-www-target-pool"
  instances = ["${google_compute_instance.www.*.self_link}"]
  health_checks = ["${google_compute_http_health_check.http.name}"]
}

resource "google_compute_forwarding_rule" "http" {
  name = "lbtest-www-http-forwarding-rule"
  target = "${google_compute_target_pool.www.self_link}"
  ip_address = "${google_compute_address.www.address}"
  port_range = "80-80"
}

resource "google_compute_forwarding_rule" "https" {
  name = "lbtest-www-https-forwarding-rule"
  target = "${google_compute_target_pool.www.self_link}"
  ip_address = "${google_compute_address.www.address}"
  port_range = "443-443"
}

resource "google_compute_http_health_check" "http" {
  name = "lbtest-www-http-basic-check"
  request_path = "/"
  check_interval_sec = 1
  healthy_threshold = 1
  unhealthy_threshold = 10
  timeout_sec = 1
}



# Instances go here
resource "google_compute_instance" "www" {
  name = "lbtest-www-1"
  machine_type = "f1-micro"
  zone = "us-east1-d"
  depends_on = ["google_compute_subnetwork.www"]

  tags = ["www-node","backend"]

  disk {
    image = "debian-cloud/debian-8"
  }

  network_interface {
    subnetwork = "lbtest-subnet2"
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
apt-get -y install aptitude
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
output "www_instance_public_ip" {
  value = "${google_compute_instance.www.network_interface.0.assigned_nat_ip}"
}
output "www_instance_private_ip" {
  value = "${google_compute_instance.www.network_interface.0.address}"
}
