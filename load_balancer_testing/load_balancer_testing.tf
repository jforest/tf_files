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
resource "google_compute_global_address" "www" {
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
resource "google_compute_global_forwarding_rule" "www" {
  name = "test"
  target = "${google_compute_target_http_proxy.www.self_link}"
  port_range = "80-80"
  ip_address = "${google_compute_global_address.www.self_link}"
}

resource "google_compute_target_http_proxy" "www" {
  name        = "test-proxy"
  description = "a description"
  url_map     = "${google_compute_url_map.www.self_link}"
}

resource "google_compute_url_map" "www" {
  name            = "url-map"
  description     = "a description"
  default_service = "${google_compute_backend_service.www.self_link}"
}

resource "google_compute_backend_service" "www" {
  name        = "www-backend"
  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 10

  backend {
    group = "${google_compute_instance_group.www.self_link}"
  }

  health_checks = ["${google_compute_http_health_check.www.self_link}"]
}

resource "google_compute_instance_group" "www" {
  name = "www-test"
  description = "www nodes instance group"
  zone = "us-east1-d"
  
  instances = ["${google_compute_instance.www.self_link}"]

  named_port {
    name = "http"
    port = "80"
  }
}

resource "google_compute_http_health_check" "www" {
  name               = "test"
  request_path       = "/"
  check_interval_sec = 1
  timeout_sec        = 1
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
  }

  scheduling {
    on_host_maintenance = "MIGRATE"
    automatic_restart = "true"
  }

  service_account {
    scopes = ["compute-ro"]
  }

  metadata_startup_script = "${file("scripts/www.sh")}"

  metadata {
    hostname = "www.foresj.net"
    sshKeys = "${var.ssh_user}:${file(var.ssh_key)}"
  }
}



output "www_public_ip" {
  value = "${google_compute_global_address.www.address}"
}
output "www_instance_private_ip" {
  value = "${google_compute_instance.www.network_interface.0.address}"
}
