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

resource "google_compute_route" "nat" {
  name        = "no-ip-internet-route"
  dest_range  = "0.0.0.0/0"
  network     = "${google_compute_network.test.self_link}"
  next_hop_instance = "nat1"
  next_hop_instance_zone = "us-east1-d"
  priority    = 800
  tags = ["no-ip"]

  depends_on = ["google_compute_instance.nat"]
}



# Static IPs here
resource "google_compute_address" "bastion" {
  name = "test-bastion-address"
}

resource "google_compute_address" "nat" {
  name = "test-nat-address"
}

resource "google_compute_global_address" "www" {
  name = "lbtest-www-address"
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

resource "google_compute_firewall" "no-ip-to-nat" {
  name = "test-no-ip-to-nat"
  network = "${google_compute_network.test.name}"
  description = "Allow all traffic ports from no-ip to nat"

  allow {
    protocol = "tcp"
    ports = ["1-65535"]
  }
  allow {
    protocol = "udp"
    ports = ["1-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_tags = ["no-ip"]
  target_tags = ["nat"]
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
  name = "test-www-1"
  machine_type = "f1-micro"
  zone = "us-east1-d"
  depends_on = ["google_compute_subnetwork.www","google_compute_firewall.no-ip-to-nat","google_compute_route.nat"]

  tags = ["www-node","backend","no-ip"]

  disk {
    image = "debian-cloud/debian-8"
  }

  network_interface {
    subnetwork = "test-subnet2"
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
    hostname = "www1.foresj.net"
    sshKeys = "${var.ssh_user}:${file(var.ssh_key)}"
  }
}

resource "google_compute_instance" "nat" {
  name = "nat1"
  machine_type = "f1-micro"
  zone = "us-east1-d"
  depends_on = ["google_compute_subnetwork.fe"]
  can_ip_forward = "true"

  tags = ["nat"]

  disk {
    image = "debian-cloud/debian-8"
  }

  network_interface {
    subnetwork = "test-subnet1"
    access_config {
      nat_ip = "${google_compute_address.nat.address}"
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
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
SCRIPT

  metadata {
    hostname = "nat.foresj.net"
    sshKeys = "${var.ssh_user}:${file(var.ssh_key)}"
  }
}



output "www_public_ip" {
  value = "${google_compute_global_address.www.address}"
}
output "bastion_public_ip" {
  value = "${google_compute_address.bastion.address}"
}
output "nat_public_ip" {
  value = "${google_compute_address.nat.address}"
}
output "www_private_ip" {
  value = "${google_compute_instance.www.network_interface.0.address}"
}
