# Set the required provider and versions
terraform {

  # COMMENT THIS OUT IF YOU WANT TO TEST LOCALLY ################
  backend "gcs" {
    bucket  = "iac-demo"
    prefix  = "terraform/state"
  }
  ###############################################################

  required_providers {
    # We recommend pinning to the specific version of the Docker Provider you're using
    # since new versions are released frequently
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.20.0"
    }
  }
}

provider "docker" {}


provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "docker-desktop" #TODO: Replace with var later
}

