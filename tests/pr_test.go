// Tests in this file are run in the PR pipeline and the continuous testing pipeline
package test

import (
	"context"
	"fmt"
	"io/fs"
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
	"github.com/terraform-ibm-modules/ibmcloud-terratest-wrapper/common"
	"github.com/terraform-ibm-modules/ibmcloud-terratest-wrapper/testhelper"
	"github.com/terraform-ibm-modules/ibmcloud-terratest-wrapper/testschematic"
)

const resourceGroup = "BRT-General-testing"
const existing_brs_instance_crn = "crn:v1:bluemix:public:backup-recovery:au-syd:a/7d8f9e928b9d6c2dfa06475946765e01:4dde55c7-e8a8-48c8-b431-c226f75090f7::"
const fullyConfigurableTerraformDir = "solutions/fully-configurable"
const iksExampleDir = "examples/kubernetes"
const ocpExampleDir = "examples/openshift"
const crossClusterExampleDir = "examples/backup-recovery-cross-cluster"

var excludeDirs = []string{".terraform", ".docs", ".github", ".git", ".idea", "common-dev-assets", "examples", "tests", "reference-architectures"}

var includeFiletypes = []string{".tf", ".yaml", ".py", ".tpl", ".md", ".sh"}

// Current supported regions
var validRegions = []string{
	"us-south",
	"us-east",
	"eu-es",
}

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

// TestMain sets up shared services before running tests.
func TestMain(m *testing.M) {
	os.Exit(m.Run())
}

// setupTerraform provisions a temporary copy of realTerraformDir, applies it,
// and returns the options. Optional extraVars are merged into the base vars
// (prefix, region, resource_group) before the apply — use this when the target
// stack declares additional variables (e.g. existing_brs_instance_crn).
func setupTerraform(t *testing.T, prefix, realTerraformDir string, extraVars ...map[string]interface{}) *terraform.Options {
	tempTerraformDir, err := files.CopyTerraformFolderToTemp(realTerraformDir, prefix)
	require.NoError(t, err, "Failed to create temporary Terraform folder")

	region := validRegions[common.CryptoIntn(len(validRegions))]

	vars := map[string]interface{}{
		"prefix":         prefix,
		"region":         region,
		"resource_group": resourceGroup,
	}
	for _, extra := range extraVars {
		for k, v := range extra {
			vars[k] = v
		}
	}

	existingTerraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: tempTerraformDir,
		Vars:         vars,
		// Set Upgrade to true to ensure latest version of providers and modules are used by terratest.
		// This is the same as setting the -upgrade=true flag with terraform.
		Upgrade: true,
	})

	terraform.InitContext(t, context.Background(), existingTerraformOptions)
	terraform.WorkspaceSelectOrNewContext(t, context.Background(), existingTerraformOptions, prefix)
	_, err = terraform.InitAndApplyContextE(t, context.Background(), existingTerraformOptions)
	require.NoError(t, err, "Init and Apply of temp existing resource failed")

	return existingTerraformOptions
}

func cleanupTerraform(t *testing.T, options *terraform.Options, prefix string) {
	if t.Failed() && strings.ToLower(os.Getenv("DO_NOT_DESTROY_ON_FAILURE")) == "true" {
		fmt.Println("Terratest failed. Debug the test and delete resources manually.")
		return
	}
	logger.Log(t, "START: Destroy (existing resources)")
	terraform.DestroyContext(t, context.Background(), options)
	terraform.WorkspaceDeleteContext(t, context.Background(), options, prefix)
	logger.Log(t, "END: Destroy (existing resources)")
}

func getSchematicTerraformVars(t *testing.T, prefix string, options *testschematic.TestSchematicOptions, existingTerraformOptions *terraform.Options) []testschematic.TestSchematicTerraformVar {
	return []testschematic.TestSchematicTerraformVar{
		{Name: "ibmcloud_api_key", Value: options.RequiredEnvironmentVars["TF_VAR_ibmcloud_api_key"], DataType: "string", Secure: true},
		{Name: "cluster_id", Value: terraform.OutputContext(t, context.Background(), existingTerraformOptions, "workload_cluster_id"), DataType: "string"},
		{Name: "cluster_resource_group_id", Value: terraform.OutputContext(t, context.Background(), existingTerraformOptions, "cluster_resource_group_id"), DataType: "string"},
		{Name: "enable_auto_protect", Value: "false", DataType: "bool"},
		{Name: "existing_brs_instance_crn", Value: existing_brs_instance_crn, DataType: "string"},
		{Name: "brs_connection_name", Value: fmt.Sprintf("%s-conn", prefix), DataType: "string"},
		{Name: "brs_endpoint_type", Value: "public", DataType: "string"},
		{Name: "cluster_config_endpoint_type", Value: "private", DataType: "string"},
		{Name: "dsc_replicas", Value: "1", DataType: "number"},
		{Name: "brs_create_new_connection", Value: "true", DataType: "bool"},
		{Name: "region", Value: terraform.OutputContext(t, context.Background(), existingTerraformOptions, "region"), DataType: "string"},
		{Name: "connection_env_type", Value: "kRoksVpc", DataType: "string"},
		{Name: "kube_type", Value: "openshift", DataType: "string"},
		{Name: "policies", Value: []map[string]interface{}{
			{
				"name":              fmt.Sprintf("%s-test-policy", prefix),
				"create_new_policy": true,
				"schedule": map[string]interface{}{
					"unit": "Hours",
					"hour_schedule": map[string]interface{}{
						"frequency": 6,
					},
				},
				"retention": map[string]interface{}{
					"duration": 4,
					"unit":     "Weeks",
				},
				"use_default_backup_target": true,
			},
		}, DataType: "list"},
	}
}

func TestRunFullyConfigurableInSchematics(t *testing.T) {
	t.Parallel()

	tarIncludePatterns, recurseErr := getTarIncludePatternsRecursively("..", excludeDirs, includeFiletypes)
	// if error producing tar patterns (very unexpected) fail test immediately
	require.NoError(t, recurseErr, "Schematic Test had unexpected error traversing directory tree")

	// Provision resources first
	prefix := fmt.Sprintf("ocp-brs-%s", strings.ToLower(random.UniqueID()))
	existingTerraformOptions := setupTerraform(t, prefix, "./resources")
	defer cleanupTerraform(t, existingTerraformOptions, prefix)

	options := testschematic.TestSchematicOptionsDefault(&testschematic.TestSchematicOptions{
		Testing:               t,
		Prefix:                "ocp-fc",
		TarIncludePatterns:    tarIncludePatterns,
		TemplateFolder:        fullyConfigurableTerraformDir,
		Tags:                  []string{"test-schematic"},
		DeleteWorkspaceOnFail: false,
	})

	options.TerraformVars = getSchematicTerraformVars(t, prefix, options, existingTerraformOptions)
	options.IgnoreUpdates = testhelper.Exemptions{
		List: []string{
			// The DSC helm release re-updates on every plan because the BRS
			// registration token rotates by design and the chart version resolves
			// dynamically. This is expected, non-destructive churn.
			"module.protect_cluster.helm_release.data_source_connector",
			// wait_before_helm_destroy stores the kubeconfig path in input for its
			// destroy-time provisioner. That path differs between Schematics jobs
			// (each runs in a fresh temp dir), causing a side-effect-free in-place
			// update (no provisioner runs on update).
			"module.protect_cluster.terraform_data.wait_before_helm_destroy",
			// wait_for_dsc_node_ready stores the kubeconfig path in input.
			// That path differs between Schematics jobs (each runs in a fresh
			// temp dir), causing a side-effect-free in-place update.
			"module.protect_cluster.terraform_data.wait_for_dsc_node_ready[0]",
			// purge_stale_dsc_pvc has registration_token in triggers_replace.
			// The token rotates by design between Schematics jobs so the resource
			// shows as [update] (replace) on re-plan. The re-run is a no-op when a
			// live DSC pod is present (upgrade path guard). Side-effect-free churn.
			"module.protect_cluster.terraform_data.purge_stale_dsc_pvc",
			// dsc_immutable_values stores the kubeconfig path in input for its
			// destroy-time PVC cleanup provisioner. That path differs between
			// Schematics jobs, causing a side-effect-free in-place update.
			"module.protect_cluster.terraform_data.dsc_immutable_values",
		},
	}
	// TODO(provider-fix): re-enable these once ibm provider PR #6906 is merged+released.
	// Schematics runs "terraform refresh" (= apply -refresh-only) before every destroy.
	// TF_CLI_ARGS_apply=-refresh=false makes it a no-op, preventing CustomizeDiff on
	// ibm_backup_recovery_connection_registration_token from hard-erroring.
	// TF_CLI_ARGS_destroy=-refresh=false skips the inline pre-destroy refresh.
	// options.AddWorkspaceEnvVar("TF_CLI_ARGS_apply", "-refresh=false", false, false)
	// options.AddWorkspaceEnvVar("TF_CLI_ARGS_destroy", "-refresh=false", false, false)
	require.NoError(t, options.RunSchematicTest(), "This should not have errored")
}

// Upgrade Test does not require KMS encryption
func TestRunUpgradeFullyConfigurable(t *testing.T) {
	t.Parallel()

	tarIncludePatterns, recurseErr := getTarIncludePatternsRecursively("..", excludeDirs, includeFiletypes)
	// if error producing tar patterns (very unexpected) fail test immediately
	require.NoError(t, recurseErr, "Schematic Test had unexpected error traversing directory tree")

	// Provision existing resources first
	prefix := fmt.Sprintf("ocp-existing-%s", strings.ToLower(random.UniqueID()))
	existingTerraformOptions := setupTerraform(t, prefix, "./resources")
	defer cleanupTerraform(t, existingTerraformOptions, prefix)

	options := testschematic.TestSchematicOptionsDefault(&testschematic.TestSchematicOptions{
		Testing:               t,
		Prefix:                "fc-upg",
		TarIncludePatterns:    tarIncludePatterns,
		TemplateFolder:        fullyConfigurableTerraformDir,
		Tags:                  []string{"test-schematic"},
		DeleteWorkspaceOnFail: false,
	})

	vars := getSchematicTerraformVars(t, prefix, options, existingTerraformOptions)
	// Override connection name to distinguish the upgrade test's connection from
	// the standard schematics test's connection when running in parallel.
	for i, v := range vars {
		if v.Name == "brs_connection_name" {
			vars[i].Value = fmt.Sprintf("%s-upgrade-conn", prefix)
		}
	}
	options.TerraformVars = vars

	options.IgnoreDestroys = testhelper.Exemptions{
		List: []string{
			"module.protect_cluster.time_rotating.token_rotation",
			"module.protect_cluster.ibm_backup_recovery_connection_registration_token.registration_token",
			"module.protect_cluster.terraform_data.cleanup_brs_agent_resources",
			"module.protect_cluster.module.backup_recovery_instance.ibm_backup_recovery_connection_registration_token.registration_token[0]",
			fmt.Sprintf(`module.protect_cluster.module.backup_recovery_instance.ibm_backup_recovery_protection_policy.protection_policy["%s-test-policy"]`, prefix),
			// wait_before_helm_destroy moved from triggers_replace to input, which
			// is a one-time structural change that forces a replace when upgrading
			// from the base version. Post-merge this becomes a plain in-place update
			// (covered by IgnoreUpdates below).
			"module.protect_cluster.terraform_data.wait_before_helm_destroy",
			// wait_for_source_discovery is replaced (delete+create) on upgrade
			// because its trigger (connection_id) changes between the base and the
			// new connection. Must be exempted from both IgnoreDestroys and IgnoreAdds.
			"module.protect_cluster.time_sleep.wait_for_source_discovery",
		},
	}
	options.IgnoreAdds = testhelper.Exemptions{
		List: []string{
			"module.protect_cluster.module.backup_recovery_instance.ibm_backup_recovery_connection_registration_token.registration_token[0]",
			"module.protect_cluster.module.backup_recovery_instance.ibm_backup_recovery_data_source_connection.connection[0]",
			fmt.Sprintf(`module.protect_cluster.module.backup_recovery_instance.ibm_backup_recovery_protection_policy.protection_policy["%s-test-policy"]`, prefix),
			// wait_for_dsc_node_ready is a new resource added in this PR that
			// does not exist in the base version. The upgrade plan will show it
			// as an add, which is expected and harmless.
			"module.protect_cluster.terraform_data.wait_for_dsc_node_ready[0]",
			// wait_for_source_discovery is replaced on upgrade because its
			// trigger (connection_id) changes between the base and new connection.
			"module.protect_cluster.time_sleep.wait_for_source_discovery",
		},
	}
	options.IgnoreUpdates = testhelper.Exemptions{
		List: []string{
			// The DSC helm release re-updates on every plan because the BRS
			// registration token rotates by design and the chart version resolves
			// dynamically. This is expected, non-destructive churn.
			"module.protect_cluster.helm_release.data_source_connector",
			// wait_before_helm_destroy stores the kubeconfig path in input for its
			// destroy-time provisioner. That path differs between Schematics jobs
			// (each runs in a fresh temp dir), causing a side-effect-free in-place
			// update (no provisioner runs on update).
			"module.protect_cluster.terraform_data.wait_before_helm_destroy",
			// wait_for_dsc_node_ready stores the kubeconfig path in input.
			// That path differs between Schematics jobs (each runs in a fresh
			// temp dir), causing a side-effect-free in-place update.
			"module.protect_cluster.terraform_data.wait_for_dsc_node_ready[0]",
			// source_registration is updated in-place on upgrade because the new
			// module version registers updated image versions against the same source.
			"module.protect_cluster.ibm_backup_recovery_source_registration.source_registration",
		},
	}

	// TODO(provider-fix): re-enable these once ibm provider PR #6906 is merged+released.
	// Same reason as TestRunFullyConfigurableInSchematics — prevents the Schematics
	// pre-destroy refresh and inline destroy refresh from hard-erroring on stale
	// ibm_backup_recovery_data_source_connection state.
	// options.AddWorkspaceEnvVar("TF_CLI_ARGS_apply", "-refresh=false", false, false)
	// options.AddWorkspaceEnvVar("TF_CLI_ARGS_destroy", "-refresh=false", false, false)
	require.NoError(t, options.RunSchematicUpgradeTest(), "This should not have errored")
}

// Shared setup function for all examples
func setupOptions(t *testing.T, prefix string, dir string, exemptionList []string) *testhelper.TestOptions {
	region := validRegions[common.CryptoIntn(len(validRegions))]
	options := testhelper.TestOptionsDefaultWithVars(&testhelper.TestOptions{
		Testing:       t,
		TerraformDir:  dir,
		Prefix:        prefix,
		ResourceGroup: resourceGroup,
		Region:        region,
		IgnoreUpdates: testhelper.Exemptions{
			List: exemptionList,
		},
	})

	if options.TerraformVars == nil {
		options.TerraformVars = map[string]interface{}{}
	}
	options.TerraformVars["existing_brs_instance_crn"] = existing_brs_instance_crn

	return options
}

func TestRunIKSExample(t *testing.T) {
	t.Parallel()

	options := setupOptions(t, "brs-iks", iksExampleDir, []string{
		"module.backup_recover_protect_ocp.ibm_backup_recovery_source_registration.source_registration",
		"ibm_container_vpc_cluster.vpc_cluster[0]",
		"ibm_container_cluster.cluster[0]",
	})
	// TODO(provider-fix): re-enable these once ibm provider PR #6906 is merged+released.
	// Without -refresh=false, stale BRS connection IDs in state cause the provider to
	// hard-error on HTTP 400 "does not exist" during the consistency-plan refresh (Plan)
	// and the pre-destroy refresh (Destroy).
	// options.PostApplyHook = func(o *testhelper.TestOptions) error {
	// 	o.TerraformOptions.ExtraArgs.Plan = append(o.TerraformOptions.ExtraArgs.Plan, "-refresh=false")
	// 	return nil
	// }
	// options.PreDestroyHook = func(o *testhelper.TestOptions) error {
	// 	o.TerraformOptions.ExtraArgs.Destroy = append(o.TerraformOptions.ExtraArgs.Destroy, "-refresh=false")
	// 	return nil
	// }

	output, err := options.RunTestConsistency()
	assert.NoError(t, err, "This should not have errored")
	assert.NotNil(t, output, "Expected some output")
}

func TestRunOCPExample(t *testing.T) {
	t.Parallel()

	options := setupOptions(t, "brs-ocp", ocpExampleDir, []string{
		"module.backup_recover_protect_ocp.ibm_backup_recovery_source_registration.source_registration",
		"module.ocp_base[0].ibm_container_vpc_cluster.cluster[0]",
		"ibm_container_cluster.cluster[0]",
	})
	// TODO(provider-fix): re-enable these once ibm provider PR #6906 is merged+released.
	// Same reason as TestRunIKSExample.
	// options.PostApplyHook = func(o *testhelper.TestOptions) error {
	// 	o.TerraformOptions.ExtraArgs.Plan = append(o.TerraformOptions.ExtraArgs.Plan, "-refresh=false")
	// 	return nil
	// }
	// options.PreDestroyHook = func(o *testhelper.TestOptions) error {
	// 	o.TerraformOptions.ExtraArgs.Destroy = append(o.TerraformOptions.ExtraArgs.Destroy, "-refresh=false")
	// 	return nil
	// }

	output, err := options.RunTestConsistency()
	assert.NoError(t, err, "This should not have errored")
	assert.NotNil(t, output, "Expected some output")
}

func TestRunCrossClusterExample(t *testing.T) {
	t.Parallel()

	options := setupOptions(t, "brs-cross", crossClusterExampleDir, []string{
		"module.source_backup_recovery.ibm_backup_recovery_source_registration.source_registration",
		"module.target_backup_recovery.ibm_backup_recovery_source_registration.source_registration",
		"module.source_backup_recovery.module.backup_recovery_instance.ibm_backup_recovery_connection_registration_token.registration_token[0]",
		"module.target_backup_recovery.module.backup_recovery_instance.ibm_backup_recovery_connection_registration_token.registration_token[0]",
		"ibm_container_vpc_cluster.source_cluster[0]",
		"ibm_container_vpc_cluster.target_cluster[0]",
	})

	options.TerraformVars["brs_create_new_connection"] = true

	options.IgnoreUpdates.List = append(options.IgnoreUpdates.List,
		fmt.Sprintf(`module.source_backup_recovery.module.backup_recovery_instance.ibm_backup_recovery_protection_policy.protection_policy["%s-continuous-backup"]`, options.Prefix),
	)
	// TODO(provider-fix): re-enable -refresh=false lines once ibm provider PR #6906 is merged+released.
	// Same reason as TestRunIKSExample. parallelism=1 is kept unconditionally — it is not
	// provider-related; it prevents VPC destroy from racing worker-node cleanup.
	// options.PostApplyHook = func(o *testhelper.TestOptions) error {
	// 	o.TerraformOptions.ExtraArgs.Plan = append(o.TerraformOptions.ExtraArgs.Plan, "-refresh=false")
	// 	return nil
	// }
	options.PreDestroyHook = func(o *testhelper.TestOptions) error {
		o.TerraformOptions.ExtraArgs.Destroy = append(o.TerraformOptions.ExtraArgs.Destroy, "-parallelism=1")
		return nil
	}

	output, err := options.RunTestConsistency()
	assert.NoError(t, err, "This should not have errored")
	assert.NotNil(t, output, "Expected some output")
}

func TestRunCrossClusterExistingConnection(t *testing.T) {
	t.Parallel()

	// Provision pre-existing BRS connections using dedicated helper directory.
	// Pass existing_brs_instance_crn so both source_connection and target_connection
	// receive a non-null CRN for their crn_parser sub-module.
	prefix := fmt.Sprintf("brs-xc-%s", strings.ToLower(random.UniqueID()))
	existingTerraformOptions := setupTerraform(t, prefix, "./resources-cross-cluster", map[string]interface{}{
		"existing_brs_instance_crn": existing_brs_instance_crn,
	})
	defer cleanupTerraform(t, existingTerraformOptions, prefix)

	// The cross-cluster example must run in the same region as the pre-provisioned
	// BRS connections so that brs_create_new_connection=false can locate them.
	// setupTerraform picks its own random region; read it back from the output.
	existingRegion := terraform.OutputContext(t, context.Background(), existingTerraformOptions, "region")

	options := setupOptions(t, prefix, crossClusterExampleDir, []string{
		"module.source_backup_recovery.ibm_backup_recovery_source_registration.source_registration",
		"module.target_backup_recovery.ibm_backup_recovery_source_registration.source_registration",
		"module.source_backup_recovery.module.backup_recovery_instance.ibm_backup_recovery_connection_registration_token.registration_token[0]",
		"module.target_backup_recovery.module.backup_recovery_instance.ibm_backup_recovery_connection_registration_token.registration_token[0]",
		"ibm_container_vpc_cluster.source_cluster[0]",
		"ibm_container_vpc_cluster.target_cluster[0]",
	})

	// Override the random region chosen by setupOptions with the one used for the
	// pre-provisioned connections so the two terraform states stay consistent.
	options.Region = existingRegion
	options.TerraformVars["region"] = existingRegion
	options.TerraformVars["existing_brs_instance_crn"] = existing_brs_instance_crn
	options.TerraformVars["brs_create_new_connection"] = false
	options.TerraformVars["source_connection_name"] = terraform.OutputContext(t, context.Background(), existingTerraformOptions, "source_connection_name")
	options.TerraformVars["target_connection_name"] = terraform.OutputContext(t, context.Background(), existingTerraformOptions, "target_connection_name")

	// The continuous-backup protection policy re-plans as an in-place update on the
	// consistency check: its backup_policy value churns by design, so the second plan
	// always shows a no-op update. Exempt it, exactly as TestRunCrossClusterExample does.
	options.IgnoreUpdates.List = append(options.IgnoreUpdates.List,
		fmt.Sprintf(`module.source_backup_recovery.module.backup_recovery_instance.ibm_backup_recovery_protection_policy.protection_policy["%s-continuous-backup"]`, options.Prefix),
	)

	// TODO(provider-fix): re-enable -refresh=false lines once ibm provider PR #6906 is merged+released.
	// Same reason as TestRunIKSExample. parallelism=1 is kept unconditionally.
	// options.PostApplyHook = func(o *testhelper.TestOptions) error {
	// 	o.TerraformOptions.ExtraArgs.Plan = append(o.TerraformOptions.ExtraArgs.Plan, "-refresh=false")
	// 	return nil
	// }
	options.PreDestroyHook = func(o *testhelper.TestOptions) error {
		o.TerraformOptions.ExtraArgs.Destroy = append(o.TerraformOptions.ExtraArgs.Destroy, "-parallelism=1")
		return nil
	}

	output, err := options.RunTestConsistency()
	assert.NoError(t, err, "This should not have errored")
	assert.NotNil(t, output, "Expected some output")
}
