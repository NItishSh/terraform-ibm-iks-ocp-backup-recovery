provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
}

# The root module (backup_recovery) manages its own helm and kubernetes
# providers internally. The example only needs the ibm provider.
