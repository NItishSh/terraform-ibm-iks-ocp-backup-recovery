
########################################################################################################################
# Test Workload Deployment (for backup validation)
########################################################################################################################

# Create namespace for test workload
resource "kubernetes_namespace_v1" "workload_ns" {
  metadata {
    name = "${var.prefix}-demo-ns"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "backup-enabled"               = "true"
    }
  }

  depends_on = [time_sleep.wait_operators]
}

########################################################################################################################
# Test Application with PVC
########################################################################################################################

# Deploy PVC for test application
resource "kubernetes_persistent_volume_claim_v1" "test_app_pvc" {
  metadata {
    name      = "app-with-vpc-block-pvc"
    namespace = kubernetes_namespace_v1.workload_ns.metadata[0].name
    labels = {
      app = "app-with-vpc-block-pvc"
    }
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.classic_cluster ? "ibmc-block-silver" : "ibmc-vpc-block-metro-5iops-tier"

    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }

  wait_until_bound = false # Don't wait for PVC to bind during apply
}

# Deploy test application with PVC
resource "kubernetes_deployment_v1" "test_app_with_pvc" {
  #checkov:skip=CKV_K8S_8:Test workload - liveness probe not required
  #checkov:skip=CKV_K8S_9:Test workload - readiness probe not required
  #checkov:skip=CKV_K8S_28:Test workload - NET_RAW capability not dropped
  #checkov:skip=CKV_K8S_29:Test workload - security context not applied
  #checkov:skip=CKV_K8S_30:Test workload - container security context not applied
  #checkov:skip=CKV_K8S_14:Test workload - using latest tag for simplicity
  #checkov:skip=CKV_K8S_43:Test workload - image digest not used
  metadata {
    name      = "app-with-vpc-block-pvc"
    namespace = kubernetes_namespace_v1.workload_ns.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "app-with-vpc-block-pvc"
      }
    }

    template {
      metadata {
        labels = {
          app = "app-with-vpc-block-pvc"
        }
      }

      spec {
        container {
          name    = "test-app"
          image   = "icr.io/ext/cohesity/busybox:latest"
          command = ["sh", "-c"]
          args = [
            <<-EOT
              echo 'Starting data generation...'
              # Create a 10GB file with random data in the PVC
              dd if=/dev/urandom of=/data/testfile.dat bs=1M count=10240
              echo 'Data generation complete. File created at /data/testfile.dat'
              # Keep the pod running
              sleep infinity
            EOT
          ]

          volume_mount {
            name       = "data-storage"
            mount_path = "/data"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "data-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.test_app_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

########################################################################################################################
# Test Application without PVC
########################################################################################################################

# Deploy test application without PVC (simpler workload)
resource "kubernetes_deployment_v1" "test_app_without_pvc" {
  #checkov:skip=CKV_K8S_8:Test workload - liveness probe not required
  #checkov:skip=CKV_K8S_9:Test workload - readiness probe not required
  #checkov:skip=CKV_K8S_28:Test workload - NET_RAW capability not dropped
  #checkov:skip=CKV_K8S_29:Test workload - security context not applied
  #checkov:skip=CKV_K8S_30:Test workload - container security context not applied
  #checkov:skip=CKV_K8S_14:Test workload - using latest tag for simplicity
  #checkov:skip=CKV_K8S_43:Test workload - image digest not used
  metadata {
    name      = "app-without-pvc"
    namespace = kubernetes_namespace_v1.workload_ns.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "app-without-pvc"
      }
    }

    template {
      metadata {
        labels = {
          app = "app-without-pvc"
        }
      }

      spec {
        container {
          name    = "test-app"
          image   = "icr.io/ext/cohesity/busybox:latest"
          command = ["sh", "-c"]
          args    = ["echo 'Pod is ready. Sleeping...'; sleep infinity"]

          resources {
            requests = {
              cpu    = "250m"
              memory = "250Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "500Mi"
            }
          }
        }
      }
    }
  }
}

########################################################################################################################
# Wait for Workload Stabilization
########################################################################################################################

# Wait for workload deployments to be ready before proceeding with protection group creation
resource "terraform_data" "wait_for_workload" {
  triggers_replace = {
    namespace           = kubernetes_namespace_v1.workload_ns.metadata[0].name
    deployment_with_pvc = kubernetes_deployment_v1.test_app_with_pvc.metadata[0].name
    deployment_no_pvc   = kubernetes_deployment_v1.test_app_without_pvc.metadata[0].name
    kubeconfig          = data.ibm_container_cluster_config.cluster_config.config_file_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      ${path.module}/../../scripts/wait_for_workload.sh \
        "${self.triggers_replace.kubeconfig}" \
        "${self.triggers_replace.namespace}" \
        "${self.triggers_replace.deployment_with_pvc}" \
        300

      ${path.module}/../../scripts/wait_for_workload.sh \
        "${self.triggers_replace.kubeconfig}" \
        "${self.triggers_replace.namespace}" \
        "${self.triggers_replace.deployment_no_pvc}" \
        300
    EOT
  }

  depends_on = [
    kubernetes_deployment_v1.test_app_with_pvc,
    kubernetes_deployment_v1.test_app_without_pvc
  ]
}
