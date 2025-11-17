########################################################################################################################
# Input variables
########################################################################################################################

#
# Module developer tips:
#   - Examples are references that consumers can use to see how the module can be consumed. They are not designed to be
#     flexible re-usable solutions for general consumption, so do not expose any more variables here and instead hard
#     code things in the example main.tf with code comments explaining the different configurations.
#   - For the same reason as above, do not add default values to the example inputs.
#

variable "ibmcloud_api_key" {
  type        = string
  description = "The IBM Cloud API Key."
  sensitive   = true
}

variable "resource_group" {
  type        = string
  description = "An existing resource group name to use for this example, if unset a new resource group will be created"
  default     = null
}

variable "prefix" {
  type        = string
  description = "A unique prefix to name all resources created by this example. Must be lowercase, no spaces, and 3–12 characters."
  default     = "brs-basic"
}

variable "resource_tags" {
  type        = list(string)
  description = "Optional list of tags to be added to created resources"
  default     = []
}

variable "region" {
  type        = string
  description = "Region to provision all resources created by this example."
  default     = "us-east"
}

variable "access_tags" {
  type        = list(string)
  description = "Optional list of access management tags to add to resources that are created"
  default     = []
}
variable "ocp_version" {
  type        = string
  description = "Version of the OCP cluster to provision"
  default     = "4.18"
}

variable "ocp_entitlement" {
  type        = string
  description = "Value that is applied to the entitlements for OCP cluster provisioning"
  default     = null
}