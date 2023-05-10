locals {
  nginx_name = "nginx"
  nginx_sha  = sha1(join("", [for f in fileset(path.module, "nginx/*") : filesha1(f)]))
}

# Build NGINX
# Create a docker image resource
resource "docker_image" "nginx" {
  name = var.target.kind == "gke" ? "${var.target.gke_config.location}-docker.pkg.dev/${var.target.gke_config.project}/${var.target.docker_registry}/nginx-test:latest" : "nginx-test:latest"
  triggers = {
    dir_sha1 = local.nginx_sha
  }
  build {
    context = "./nginx"
    # tag     = ["local-nginx:latest"]
    label = {
      author : "PaulFlorea"
    }

    auth_config {
      host_name = var.target.kind == "gke" ? "https://${var.target.gke_config.location}-docker.pkg.dev/${var.target.gke_config.project}/${var.target.docker_registry}" : ""
      auth      = var.target.kind == "gke" ? data.google_client_config.current[0].access_token : null
    }
  }
}

resource "docker_registry_image" "nginx" {
  count         = var.target.kind == "gke" ? 1 : 0
  name          = docker_image.nginx.name
  keep_remotely = true
}


# Enable GKE API
resource "google_project_service" "project" {
  count   = var.target.kind == "gke" ? 1 : 0
  project = var.target.gke_config.project
  service = "container.googleapis.com"
}

# GKE Cluster
# Default network and nodepool for simplicity
resource "google_container_cluster" "primary" {
  count = var.target.kind == "gke" ? 1 : 0

  name     = var.target.gke_config.cluster_name
  project  = var.target.gke_config.project
  location = var.target.gke_config.zone

  remove_default_node_pool = true
  initial_node_count       = 1

  cluster_autoscaling {
    auto_provisioning_defaults {
      disk_size = 20
      disk_type = "pd-standard"
    }
  }
}

resource "google_container_node_pool" "demo_pool" {
  count = var.target.kind == "gke" ? 1 : 0

  name       = "demo-pool"
  location   = var.target.gke_config.zone
  project    = var.target.gke_config.project
  cluster    = google_container_cluster.primary[0].name
  node_count = 1

  node_config {
    machine_type = "e2-small"
  }
}

data "google_client_config" "current" {
  count = var.target.kind == "gke" ? 1 : 0
}

# Init Kubernetes after the cluster is generated

provider "kubernetes" {
  # Local connection vars
  config_path    = var.target.kind != "gke" ? "~/.kube/config" : null
  config_context = var.target.kind != "gke" ? "docker-desktop" : null

  # Remote connnection vars
  host                   = var.target.kind == "gke" ? "https://${google_container_cluster.primary[0].endpoint}" : null
  cluster_ca_certificate = var.target.kind == "gke" ? base64decode(google_container_cluster.primary[0].master_auth.0.cluster_ca_certificate) : null
  token                  = var.target.kind == "gke" ? data.google_client_config.current[0].access_token : null
}

# Namespace
resource "kubernetes_namespace" "nginx" {
  metadata {
    name = local.nginx_name
  }
}

# 2 Replicasets
# * 0.5vcpu & 512Mi Limit
resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = local.nginx_name
    namespace = kubernetes_namespace.nginx.metadata[0].name
    labels = {
      app = local.nginx_name
      # Triggers redeploy on code changes
      app_sha = local.nginx_sha
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = local.nginx_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.nginx_name
        }
      }

      spec {
        container {
          # image             = "${docker_image.nginx.build.*.auth_config[0][0].host_name}${docker_image.nginx.build.*.tag[0][0]}"
          image             = docker_image.nginx.name
          name              = local.nginx_name
          image_pull_policy = "IfNotPresent"

          volume_mount {
            mount_path = "/var/log/nginx/"
            name       = kubernetes_persistent_volume_claim.nginx.metadata[0].name
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }

            initial_delay_seconds = 3
            period_seconds        = 3
          }

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }
        }
        volume {
          name = kubernetes_persistent_volume_claim.nginx.metadata[0].name
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.nginx.metadata[0].name
          }
        }
      }
    }
  }
}

# * ClusterIP + Port 8080
resource "kubernetes_service" "nginx" {
  metadata {
    name      = local.nginx_name
    namespace = kubernetes_namespace.nginx.metadata[0].name
  }
  spec {
    selector = {
      app = kubernetes_deployment.nginx.metadata[0].name
    }
    port {
      port        = 8080
      target_port = 80
    }

    type = "ClusterIP"
  }
}

# * 1 Persistent Volume
#   * 2Gi capacity
#   * local file path (e.g., `${PWD}/pvc`)
resource "kubernetes_persistent_volume_claim" "nginx" {
  metadata {
    name      = "${local.nginx_name}-pvc"
    namespace = kubernetes_namespace.nginx.metadata[0].name
    labels = {
      type = var.target.kind != "gke" ? "host_path" : "standard"
    }
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.target.kind != "gke" ? "manual" : "standard-rwo"
    resources {
      requests = {
        storage = "2Gi"
      }
    }
    volume_name = kubernetes_persistent_volume.nginx.metadata[0].name
  }
}

# Don't need to define this in GKE
resource "kubernetes_persistent_volume" "nginx" {
  # count = var.target.kind != "gke" ? 1 : 0

  metadata {
    name = "${local.nginx_name}-pv"
    labels = {
      type = "host_path"
    }
  }
  spec {
    capacity = {
      storage = "2Gi"
    }
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.target.kind != "gke" ? "manual" : "standard-rwo"

    persistent_volume_source {
      host_path {
        path = var.target.kind != "gke" ? "${path.cwd}/pvc" : "/tmp"
      }
    }
  }
}
