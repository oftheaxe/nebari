resource "kubernetes_deployment" "worker" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels = {
      role = var.name
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        role = var.name
      }
    }

    template {
      metadata {
        labels = {
          role = var.name
        }
        annotations = var.deployment-annotations
      }

      spec {
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = var.node_group.key
                  operator = "In"
                  values = [
                    var.node_group.value
                  ]
                }
              }
            }
          }
        }

        container {
          name  = "conda-store-worker"
          image = "${var.conda_store_image}:${var.conda_store_image_tag}"

          args = [
            "conda-store-worker",
            "--config",
            "/etc/conda-store/conda_store_config.py"
          ]

          resources {
            requests = var.conda_store_worker_resources["requests"]
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/conda-store"
          }

          volume_mount {
            name       = "environments"
            mount_path = "/opt/environments"
          }

          volume_mount {
            name       = "storage"
            mount_path = "/home/conda"
          }

          volume_mount {
            name       = "secret"
            mount_path = "/var/lib/conda-store/"
          }
        }

        container {
          name  = "nfs-server"
          image = "gcr.io/google_containers/volume-nfs:0.8"

          port {
            name           = "nfs"
            container_port = 2049
          }

          port {
            name           = "mountd"
            container_port = 20048
          }

          port {
            name           = "rpcbind"
            container_port = 111
          }

          security_context {
            privileged = true
          }

          volume_mount {
            mount_path = "/exports"
            name       = "storage"
          }
        }

        dynamic "volume" {
          for_each = var.conda-store-worker-volumes
          content {
            name = volume.value.name

            dynamic "config_map" {
              for_each = volume.value.config_map_name != null ? [1] : []
              content {
                name = volume.value.config_map_name
              }
            }

            dynamic "secret" {
              for_each = volume.value.secret_name != null ? [1] : []
              content {
                secret_name = volume.value.secret_name
              }
            }

            dynamic "persistent_volume_claim" {
              for_each = volume.value.claim_name != null ? [1] : []
              content {
                claim_name = volume.value.claim_name
              }
            }
          }
        }

        security_context {
          run_as_group = 0
          run_as_user  = 0
        }
      }
    }
  }
}

resource "kubernetes_manifest" "scaledobject" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"

    metadata = {
      name      = "scaled-conda-worker"
      namespace = var.namespace
    }

    spec = {
      scaleTargetRef = {
        kind = "Deployment"
        name = "nebari-conda-store-worker"
      }
      maxReplicaCount = var.max-worker-replica-count
      pollingInterval = 5
      cooldownPeriod  = 5
      triggers = [
        {
          type = "postgresql"
          metadata = {
            query            = var.keda-scaling-query
            targetQueryValue = "${var.keda-target-query-value}"
            host             = "nebari-conda-store-postgresql"
            userName         = "postgres"
            port             = "5432"
            dbName           = "conda-store"
            sslmode          = "disable"
          }
          authenticationRef = {
            name = "trigger-auth-postgres"
          }
        }
      ]
    }
  }
  depends_on = [
    kubernetes_deployment.worker,
  ]
}
