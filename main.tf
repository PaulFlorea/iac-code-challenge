# Build NGINX
# Create a docker image resource
resource "docker_image" "nginx" {
  name = "nginx"
  build {
    context = "./nginx"
    tag     = ["local-nginx:latest"]
    label = {
      author : "PaulFlorea"
    }
    
    # auth_config {
      
    # }
  }
}

# Namespace


# 2 Replicasets
# * 0.5vcpu & 512Mi Limit


# * ClusterIP + Port 8080


# * 1 Persistent Volume
#   * 2Gi capacity
#   * local file path (e.g., `${PWD}/pvc`)


# * Set nginx logs to write to the above PVC

