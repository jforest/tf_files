provider "google" {
  credentials = "${file("/Users/jforest/.secure/creds.json")}"
  project     = "learning-149919"
  region      = "europe-west1"
}

resource "google_compute_network" "veuretest" {
  name       = "veuretest"
}

resource "google_compute_subnetwork" "veure-1" {
  name          = "veure-1"
  ip_cidr_range = "10.220.0.0/24"
  network       = "${google_compute_network.veuretest.self_link}"
  region        = "europe-west1"
}

resource "google_compute_subnetwork" "veure-2" {
  name          = "veure-2"
  ip_cidr_range = "10.220.1.0/24"
  network       = "${google_compute_network.veuretest.self_link}"
  region        = "europe-west1"
}
