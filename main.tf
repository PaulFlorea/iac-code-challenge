locals {
  nginx_sha = sha1(join("", [for f in fileset(path.module, "nginx/*") : filesha1(f)]))
}

# Build NGINX
# Create a docker image resource
resource "docker_image" "nginx" {
  name = "nginx"
  triggers = {
    dir_sha1 = local.nginx_sha
  }
  build {
    context = "./nginx"
    tag     = ["local-nginx:latest"]
    label = {
      author : "PaulFlorea"
    }
    
    auth_config {
      host_name = var.target.kind == "gke" ? "https://${var.target.gke_config.location}-docker.pkg.dev/${var.target.gke_config.project}/${var.target.docker_registry}" : ""
    }
  }
}

resource "docker_registry_image" "nginx" {
  count = var.target.kind == "gke" ? 1 : 0
  name          = docker_image.nginx.name
}

# Namespace
resource "kubernetes_namespace" "nginx" {
  metadata {
    # annotations = {
    #   name = "example-annotation"
    # }

    # labels = {
    #   mylabel = "label-value"
    # }

    name = "nginx"
  }
}

# 2 Replicasets
# * 0.5vcpu & 512Mi Limit
resource "kubernetes_replication_controller" "nginx" {
  metadata {
    name = "nginx"
    namespace = kubernetes_namespace.nginx.metadata[0].name
    labels = {
      app_sha = local.nginx_sha
    }
  }

  spec {
    selector = {
      test = "test_nginx"
    }
    template {
      metadata {
        labels = {
          test = "test_nginx"
        }
        annotations = {
          "app_sha" = local.nginx_sha
        }
      }

      spec {
        container {
          image = "${docker_image.nginx.build.*.auth_config[0][0].host_name}${docker_image.nginx.build.*.tag[0][0]}"
          name  = docker_image.nginx.name
          image_pull_policy = "IfNotPresent"

          liveness_probe {
            http_get {
              path = "/"
              port = 80

              http_header {
                name  = "X-Custom-Header"
                value = "Awesome"
              }
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
      }
    }
  }
}

# * ClusterIP + Port 8080


# * 1 Persistent Volume
#   * 2Gi capacity
#   * local file path (e.g., `${PWD}/pvc`)


# * Set nginx logs to write to the above PVC

