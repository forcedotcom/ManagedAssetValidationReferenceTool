public with sharing class AssetValidator {
    // Declare a property to store the asset id
    public Id assetId {get; set;}
  
   // Declare a property to store the validation result of successful validations
    public List<String> successMessages {
        get { return ValidationResults.successMessages; }
        set { successMessages = value; }
    }

    // Declare a property to store the validation result of failed validations
    public List<String> errorMessages {
        get { return ValidationResults.errorMessages; }
        set { errorMessages = value; }
    }

    // Declare a constructor to initialize the properties
    public AssetValidator() {
        assetId = null;
        successMessages = new List<String>();
        errorMessages = new List<String>();
    }
   
    // Declare a method to validate the asset status
    public void validateAssetForCPQPlusOrBilling() {
        clearResults();
        Asset asset = AssetValidatorUtil.getAssetForAssetId(assetId); 
        AssetValidatorUtil.validateAssetInputFields(asset);
        List<AssetStatePeriod> asps = AssetValidatorUtil.queryASPs(assetId);
        AssetValidatorUtil.validateASPandLifecycleDates(asset, asps);
        List<AssetAction> assetActions = AssetValidatorUtil.queryAAs(assetId);
        AssetValidatorUtil.validateAssetActionsForCPQPlusOrBilling(assetActions);
        List<AssetActionSource> assetActionSources = AssetValidatorUtil.queryAASs(assetId);
        AssetValidatorUtil.validateAssetActionSourcesForCPQPlusOrBilling(assetActionSources);
        system.debug(errorMessages);
    }

    public void validateAssetForSubMgmt() {
        clearResults();
        Asset asset = AssetValidatorUtil.getAssetForAssetId(assetId);
        AssetValidatorUtil.validateAssetInputFields(asset);
        List<AssetStatePeriod> asps = AssetValidatorUtil.queryASPs(assetId);
        AssetValidatorUtil.validateASPForSubMgmt(asset, asps);
        List<AssetAction> assetActions = AssetValidatorUtil.queryAAs(assetId);
        List<AssetActionSource> assetActionSources = AssetValidatorUtil.queryAASs(assetId);
        AssetValidatorUtil.validateAASAndAAForSubMgmt(assetActions, assetActionSources);
        AssetValidatorUtil.validateTotalLifecycleAmount(asset, assetActions);
        system.debug(errorMessages);
    }

    public void validateSubMgmtAssetBundleStructure() {
        clearResults();
        AssetBundleValidatorUtil.validate(assetId);
        system.debug(errorMessages);
    }

    private void clearResults() {
        successMessages = new List<String>();
        errorMessages = new List<String>();
        ValidationResults.clearResults();
    }
}