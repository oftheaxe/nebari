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

        annotations = {
          "checksum/config-map"         = sha256(jsonencode(kubernetes_config_map.conda-store-config.data))
          "checksum/secret"             = sha256(jsonencode(kubernetes_secret.conda-store-secret.data))
          "checksum/conda-environments" = sha256(jsonencode(kubernetes_config_map.conda-store-environments.data))
        }
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

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.conda-store-config.metadata.0.name
          }
        }

        volume {
          name = "secret"
          secret {
            secret_name = kubernetes_secret.conda-store-secret.metadata.0.name
          }
        }

        volume {
          name = "environments"
          config_map {
            name = kubernetes_config_map.conda-store-environments.metadata.0.name
          }
        }

        volume {
          name = "storage"
          persistent_volume_claim {
            claim_name = "${var.name}-conda-store-storage"
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
