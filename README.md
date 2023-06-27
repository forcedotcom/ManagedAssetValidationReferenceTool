# LifecycleManagedAssetValidationReferenceTool

This project is a reference implementation for validating lifecycle-managed assets modified by SObject APIs.
## Salesforce DX Project: Next Steps

Now that you’ve created a Salesforce DX project, what’s next? Here are some documentation resources to get you started.

## How Do You Plan to Deploy Your Changes?

Do you want to deploy a set of changes, or create a self-contained application? Choose a [development model](https://developer.salesforce.com/tools/vscode/en/user-guide/development-models).

## Configure Your Salesforce DX Project

The `sfdx-project.json` file contains useful configuration information for your project. See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm) in the _Salesforce DX Developer Guide_ for details about this file.

## Read All About It

- [Salesforce Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
- [Salesforce CLI Setup Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)

## How do you invoke this tool through UI
- Open AssetValidatorUI.vfp visualforce page on developer console.
- Click on Preview button on top-left corner.
- Enter the Asset Id to validate on visualforce page and click on one of the validation buttons according to your desired validation type.
- Results will be displayed on the same visualforce page.
- Depending on if you'd like to keep the results on the page, click on the Clear button to clear current results.

## How do you invoke this tool Anonymous window
- Open Execute anonynous window on developer console.
- Replace asset_Id with asset id you want to validate and call the desired validation function. For example:

```
AssetValidator av = new AssetValidator();
av.assetId = 'asset_Id';
av.validateAssetForCPQPlusOrBilling();
```
- Open debug logs to verify result of validation.
