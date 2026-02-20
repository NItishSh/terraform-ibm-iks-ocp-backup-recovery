// Tests in this file are run in the PR pipeline and the continuous testing pipeline
package test

import (
	"fmt"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/files"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/terraform-ibm-modules/ibmcloud-terratest-wrapper/cloudinfo"
	"github.com/terraform-ibm-modules/ibmcloud-terratest-wrapper/common"
	"github.com/terraform-ibm-modules/ibmcloud-terratest-wrapper/testhelper"
	"github.com/terraform-ibm-modules/ibmcloud-terratest-wrapper/testschematic"
)

// Use existing resource group
const resourceGroup = "geretain-test-resources"
const fullyConfigurableTerraformDir = "solutions/fully-configurable"
const iksExampleDir = "examples/kubernetes"

var excludeDirs = []string{".terraform", ".docs", ".github", ".git", ".idea", "common-dev-assets", "examples", "tests", "reference-architectures"}

var includeFiletypes = []string{".tf", ".yaml", ".py", ".tpl", ".md", ".sh"}

// Define a struct with fields that match the structure of the YAML data
const yamlLocation = "../common-dev-assets/common-go-assets/common-permanent-resources.yaml"

var (
	sharedInfoSvc      *cloudinfo.CloudInfoService
	permanentResources map[string]interface{}
)

type tarIncludePatterns struct {
	excludeDirs []string

	includeFiletypes []string

	includeDirs []string
}

func getTarIncludePatternsRecursively(dir string, dirsToExclude []string, fileTypesToInclude []string) ([]string, error) {
	r := tarIncludePatterns{dirsToExclude, fileTypesToInclude, nil}
	err := filepath.WalkDir(dir, func(path string, entry fs.DirEntry, err error) error {
		return walk(&r, path, entry, err)
	})
	if err != nil {
		fmt.Println("error")
		return r.includeDirs, err
	}
	return r.includeDirs, nil
}

func walk(r *tarIncludePatterns, s string, d fs.DirEntry, err error) error {
	if err != nil {
		return err
	}
	if d.IsDir() {
		for _, excludeDir := range r.excludeDirs {
			if strings.Contains(s, excludeDir) {
				return nil
			}
		}
		if s == ".." {
			r.includeDirs = append(r.includeDirs, "*.tf")
			return nil
		}
		for _, includeFiletype := range r.includeFiletypes {
			r.includeDirs = append(r.includeDirs, strings.ReplaceAll(s+"/*"+includeFiletype, "../", ""))
		}
	}
	return nil
}

// TestMain will be run before any parallel tests, used to set up a shared InfoService object to track region usage
// for multiple tests
func TestMain(m *testing.M) {
	sharedInfoSvc, _ = cloudinfo.NewCloudInfoServiceFromEnv("TF_VAR_ibmcloud_api_key", cloudinfo.CloudInfoServiceOptions{})

	var err error
	permanentResources, err = common.LoadMapFromYaml(yamlLocation)
	if err != nil {
		log.Fatal(err)
	}

	os.Exit(m.Run())
}

func setupTerraform(t *testing.T, prefix, realTerraformDir string) *terraform.Options {
	tempTerraformDir, err := files.CopyTerraformFolderToTemp(realTerraformDir, prefix)
	require.NoError(t, err, "Failed to create temporary Terraform folder")
	region := "us-east"

	existingTerraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: tempTerraformDir,
		Vars: map[string]interface{}{
			"prefix":         prefix,
			"region":         region,
			"resource_group": resourceGroup,
		},
		// Set Upgrade to true to ensure latest version of providers and modules are used by terratest.
		// This is the same as setting the -upgrade=true flag with terraform.
		Upgrade: true,
	})

	terraform.WorkspaceSelectOrNew(t, existingTerraformOptions, prefix)
	_, err = terraform.InitAndApplyE(t, existingTerraformOptions)
	require.NoError(t, err, "Init and Apply of temp existing resource failed")

	return existingTerraformOptions
}

func cleanupTerraform(t *testing.T, options *terraform.Options, prefix string) {
	if t.Failed() && strings.ToLower(os.Getenv("DO_NOT_DESTROY_ON_FAILURE")) == "true" {
		fmt.Println("Terratest failed. Debug the test and delete resources manually.")
		return
	}
	logger.Log(t, "START: Destroy (existing resources)")
	terraform.Destroy(t, options)
	terraform.WorkspaceDelete(t, options, prefix)
	logger.Log(t, "END: Destroy (existing resources)")
}

func TestRunFullyConfigurableInSchematics(t *testing.T) {
	t.Parallel()

	tarIncludePatterns, recurseErr := getTarIncludePatternsRecursively("..", excludeDirs, includeFiletypes)
	// if error producing tar patterns (very unexpected) fail test immediately
	require.NoError(t, recurseErr, "Schematic Test had unexpected error traversing directory tree")

	// Provision resources first
	prefix := fmt.Sprintf("ocp-brs-%s", strings.ToLower(random.UniqueId()))
	existingTerraformOptions := setupTerraform(t, prefix, "./resources")

	options := testschematic.TestSchematicOptionsDefault(&testschematic.TestSchematicOptions{
		Testing:               t,
		Prefix:                "ocp-fc",
		TarIncludePatterns:    tarIncludePatterns,
		TemplateFolder:        fullyConfigurableTerraformDir,
		Tags:                  []string{"test-schematic"},
		DeleteWorkspaceOnFail: false,
	})

	options.TerraformVars = []testschematic.TestSchematicTerraformVar{
		{Name: "ibmcloud_api_key", Value: options.RequiredEnvironmentVars["TF_VAR_ibmcloud_api_key"], DataType: "string", Secure: true},
		{Name: "cluster_id", Value: terraform.Output(t, existingTerraformOptions, "workload_cluster_id"), DataType: "string"},
		{Name: "cluster_resource_group_id", Value: terraform.Output(t, existingTerraformOptions, "cluster_resource_group_id"), DataType: "string"},
		{Name: "enable_auto_protect", Value: "false", DataType: "bool"},
		{Name: "brs_instance_crn", Value: terraform.Output(t, existingTerraformOptions, "brs_instance_crn"), DataType: "string"},
		{Name: "brs_connection_name", Value: terraform.Output(t, existingTerraformOptions, "brs_connection_name"), DataType: "string"},
		{Name: "brs_endpoint_type", Value: "private", DataType: "string"},
		{Name: "cluster_config_endpoint_type", Value: "private", DataType: "string"},
		{Name: "dsc_replicas", Value: "1", DataType: "number"},
		{Name: "policy", Value: fmt.Sprintf("{name = %q}", terraform.Output(t, existingTerraformOptions, "protection_policy_name")), DataType: "string"},
		{Name: "brs_create_new_connection", Value: "false", DataType: "bool"},
		{Name: "brs_instance_name", Value: terraform.Output(t, existingTerraformOptions, "brs_instance_name"), DataType: "string"},
		{Name: "region", Value: terraform.Output(t, existingTerraformOptions, "region"), DataType: "string"},
	}
	require.NoError(t, options.RunSchematicTest(), "This should not have errored")
	cleanupTerraform(t, existingTerraformOptions, prefix)
}

// Upgrade Test does not require KMS encryption
func TestRunUpgradeFullyConfigurable(t *testing.T) {
	t.Parallel()

	tarIncludePatterns, recurseErr := getTarIncludePatternsRecursively("..", excludeDirs, includeFiletypes)
	// if error producing tar patterns (very unexpected) fail test immediately
	require.NoError(t, recurseErr, "Schematic Test had unexpected error traversing directory tree")

	// Provision existing resources first
	prefix := fmt.Sprintf("ocp-existing-%s", strings.ToLower(random.UniqueId()))
	existingTerraformOptions := setupTerraform(t, prefix, "./resources")

	options := testschematic.TestSchematicOptionsDefault(&testschematic.TestSchematicOptions{
		Testing:               t,
		Prefix:                "fc-upg",
		TarIncludePatterns:    tarIncludePatterns,
		TemplateFolder:        fullyConfigurableTerraformDir,
		Tags:                  []string{"test-schematic"},
		DeleteWorkspaceOnFail: false,
	})

	options.TerraformVars = []testschematic.TestSchematicTerraformVar{
		{Name: "ibmcloud_api_key", Value: options.RequiredEnvironmentVars["TF_VAR_ibmcloud_api_key"], DataType: "string", Secure: true},
		{Name: "cluster_id", Value: terraform.Output(t, existingTerraformOptions, "workload_cluster_id"), DataType: "string"},
		{Name: "cluster_resource_group_id", Value: terraform.Output(t, existingTerraformOptions, "cluster_resource_group_id"), DataType: "string"},
		{Name: "enable_auto_protect", Value: "false", DataType: "bool"},
		{Name: "brs_instance_crn", Value: terraform.Output(t, existingTerraformOptions, "brs_instance_crn"), DataType: "string"},
		{Name: "brs_connection_name", Value: terraform.Output(t, existingTerraformOptions, "brs_connection_name"), DataType: "string"},
		{Name: "brs_endpoint_type", Value: "private", DataType: "string"},
		{Name: "cluster_config_endpoint_type", Value: "private", DataType: "string"},
		{Name: "dsc_replicas", Value: "1", DataType: "number"},
		{Name: "policy", Value: fmt.Sprintf("{name = %q}", terraform.Output(t, existingTerraformOptions, "protection_policy_name")), DataType: "string"},
		{Name: "brs_create_new_connection", Value: "false", DataType: "bool"},
		{Name: "brs_instance_name", Value: terraform.Output(t, existingTerraformOptions, "brs_instance_name"), DataType: "string"},
		{Name: "region", Value: terraform.Output(t, existingTerraformOptions, "region"), DataType: "string"},
	}

	// Exempt expected resource changes from image version update (7.2.16 -> 7.2.17)
	// and chart rename (cohesity-dsc-chart -> brs-ds-connector-chart)
	options.IgnoreUpdates = testhelper.Exemptions{
		List: []string{
			"module.protect_cluster.helm_release.data_source_connector",
			"module.protect_cluster.ibm_backup_recovery_source_registration.source_registration",
			"module.protect_cluster.kubernetes_cluster_role_binding_v1.brsagent_admin",
		},
	}
	options.IgnoreDestroys = testhelper.Exemptions{
		List: []string{
			"module.protect_cluster.kubernetes_secret_v1.brsagent_token",
			"module.protect_cluster.kubernetes_service_account_v1.brsagent",
		},
	}

	require.NoError(t, options.RunSchematicUpgradeTest(), "This should not have errored")
	cleanupTerraform(t, existingTerraformOptions, prefix)
}

// ibm_backup_recovery_source_registration requires ignoring updates to kubernetes_params fields which will be fixed in future provider versions
func setupIKSOptions(t *testing.T, prefix string, dir string) *testhelper.TestOptions {
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

func TestRunIKSExample(t *testing.T) {
	t.Parallel()

	options := setupIKSOptions(t, "brs-adv", iksExampleDir)

	output, err := options.RunTestConsistency()
	assert.Nil(t, err, "This should not have errored")
	assert.NotNil(t, output, "Expected some output")
}
