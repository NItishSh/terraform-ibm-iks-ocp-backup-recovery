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

variable "region" {
  type        = string
  description = "Region to provision all resources created by this example."
}