provider "google" {
  credentials = "${file("/Users/jforest/.secure/creds.json")}"
  project     = "learning-149919"
  region      = "us-east-1"
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

resource "google_compute_instance" "lucca" {
  name         = "lucca"
  machine_type = "n1-standard-1"
  zone         = "us-east1-d"

  tags = ["lucca.foresj.net", "lucca", "personal"]

  disk {
    image = "ubuntu-os-cloud/ubuntu-1604-lts"
  }

  // Local SSD disk
  disk {
    type    = "local-ssd"
    scratch = true
  }

  network_interface {
    network = "${google_compute_subnetwork.lucca1.self_link}"
    access_config {
      nat_ip = "${google_compute_address.lucca-address.self_link}"
    }
  }

  metadata {
    hostname = "lucca.foresj.net"
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
