// Tests in this file are run in the PR pipeline and the continuous testing pipeline
package test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/terraform-ibm-modules/ibmcloud-terratest-wrapper/common"
)

// Ensure every example directory has a corresponding test
const ocpClassicExampleDir = "examples/openshift"
const iksClassicExampleDir = "examples/kubernetes"

func TestRunIKSClassicExample(t *testing.T) {
	t.Parallel()

	region := validRegions[common.CryptoIntn(len(validRegions))]
	options := setupOptions(t, "brs-iksc", iksClassicExampleDir, []string{
		"module.backup_recover_protect_ocp.ibm_backup_recovery_source_registration.source_registration",
		"ibm_container_vpc_cluster.cluster[0]",
		"ibm_container_cluster.cluster[0]",
	})

	options.TerraformVars = map[string]interface{}{
		"classic_cluster":           true,
		"prefix":                    "brs-iks-classic",
		"region":                    region,
		"resource_group":            resourceGroup,
		"existing_brs_instance_crn": permanentResources["brs_us_east_crn"].(string),
	}

	output, err := options.RunTestConsistency()
	assert.Nil(t, err, "This should not have errored")
	assert.NotNil(t, output, "Expected some output")
}

func TestRunOCPClassicExample(t *testing.T) {
	t.Parallel()

	region := validRegions[common.CryptoIntn(len(validRegions))]
	options := setupOptions(t, "brs-ocpc", ocpClassicExampleDir, []string{
		"module.backup_recover_protect_ocp.ibm_backup_recovery_source_registration.source_registration",
		"module.ocp_base[0].ibm_container_vpc_cluster.cluster[0]",
		"ibm_container_cluster.classic_cluster[0]",
	})

	options.TerraformVars = map[string]interface{}{
		"classic_cluster":           true,
		"prefix":                    "brs-ocp-classic",
		"region":                    region,
		"resource_group":            resourceGroup,
		"existing_brs_instance_crn": permanentResources["brs_us_east_crn"].(string),
	}

	output, err := options.RunTestConsistency()
	assert.Nil(t, err, "This should not have errored")
	assert.NotNil(t, output, "Expected some output")
}
