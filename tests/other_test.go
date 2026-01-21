// Tests in this file are run in the PR pipeline and the continuous testing pipeline
package test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/terraform-ibm-modules/ibmcloud-terratest-wrapper/testhelper"
)

// Ensure every example directory has a corresponding test
const ocpExampleDir = "examples/openshift"

// ibm_backup_recovery_source_registration requires ignoring updates to kubernetes_params fields which will be fixed in future provider versions
func setupOcpOptions(t *testing.T, prefix string, dir string) *testhelper.TestOptions {
	region := "us-east"
	options := testhelper.TestOptionsDefaultWithVars(&testhelper.TestOptions{
		Testing:       t,
		TerraformDir:  dir,
		Prefix:        prefix,
		ResourceGroup: resourceGroup,
		Region:        region,
	})
	return options
}

func TestRunOCPExample(t *testing.T) {
	t.Parallel()

	options := setupOcpOptions(t, "brs", ocpExampleDir)

	output, err := options.RunTestConsistency()
	assert.Nil(t, err, "This should not have errored")
	assert.NotNil(t, output, "Expected some output")
}
