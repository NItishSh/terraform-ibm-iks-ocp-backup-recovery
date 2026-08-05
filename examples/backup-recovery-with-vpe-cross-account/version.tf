terraform {
  required_version = ">= 1.9.0"
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = ">= 2.2.2, < 3.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1.0, < 4.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.0.1, < 4.0.0"
    }
  }
}
