/**
 * Helper class to provide utils for Asset bundle validation
 *
 * @author rev volans
 * @since 246
 */
public with sharing class AssetBundleValidatorUtil {
    public static void validate(Id assetId) {
        List<AssetRelationship> allAssetRelationships = new List<AssetRelationship>();
        Set<String> actualAssetIds = new Set<String>();

        // Gets all asset ids and asset relationships in the bundle
        populateARAndAssetId(assetId, allAssetRelationships, actualAssetIds);

        // Validate that every AssetRelationship record contains the same groupingKey
        validateGroupingKeys(allAssetRelationships);

        if (!actualAssetIds.isEmpty()) {
            // Gets mapping of asset to asset id
            Map<String, Asset> assetIdToAsset = getAssetIdToAsset(actualAssetIds);

            // Validate fields, groupingKey, and multiple parents
            validateFields(allAssetRelationships, assetIdToAsset);

            // Validate bundle size
            validateBundleSize(allAssetRelationships);
            
            // Validate bundle depth
            validateBundleDepth(allAssetRelationships.get(0).groupingKey);
        }
    }
    
    /**
    * Constructs a list of asset relationships and a list of asset ids in the bundle belonging to the specificed asset id.
    */
    private static void populateARAndAssetId(Id assetId, List<AssetRelationship> allAssetRelationships, Set<String> actualAssetIds) {
        Set<String> assetIdToBeQueried = new Set<String>();
        List<AssetRelationship> givenAssetARRecord;
        if (Schema.sObjectType.AssetRelationship.isAccessible()) {
            givenAssetARRecord = [SELECT Id, assetId, relatedAssetId, assetRole, relatedAssetRole, groupingKey, fromDate, productRelationshipTypeId from assetRelationship WHERE assetId=:assetId OR relatedAssetId=:assetId];
        } else {
            throw new CustomException('Cannot access the AssetRelationship entity, check your permissions.');
        }
        

        if (givenAssetARRecord.isEmpty()) {
            ValidationResults.errorMessages.add('This Asset is not part of a bundle.');
            return;
        }

        actualAssetIds.add(assetId);

        // Constructs the primary and related asset ids that contain the given asset id
        for(AssetRelationship ar : givenAssetARRecord){
            if (!actualAssetIds.contains(ar.assetId)) {    
                    assetIdToBeQueried.add(ar.assetId);
                    actualAssetIds.add(ar.assetId);
                    allAssetRelationships.add(ar);
            }
            if (!actualAssetIds.contains(ar.relatedAssetId)) {
                    assetIdToBeQueried.add(ar.relatedAssetId);
                    actualAssetIds.add(ar.relatedAssetId);
                    allAssetRelationships.add(ar);
            }
        }

        // Constructs the remaining asset ids in the bundle
        while(assetIdToBeQueried.size() > 0) {
            List<AssetRelationship> assetToBeQueriedARRecord;
            if (Schema.sObjectType.AssetRelationship.isAccessible()) {
                assetToBeQueriedARRecord = [SELECT Id, assetId, relatedAssetId, assetRole, relatedAssetRole, groupingKey, fromDate, productRelationshipTypeId FROM assetRelationship WHERE assetId IN :assetIdToBeQueried OR relatedAssetId IN :assetIdToBeQueried];
            } else {
                throw new CustomException('Cannot access the AssetRelationship entity, check your permissions.');
            }
            actualAssetIds.addAll(assetIdToBeQueried);
            assetIdToBeQueried = new Set<String>(); 
            for(AssetRelationship ar : assetToBeQueriedARRecord) {
                if (!actualAssetIds.contains(ar.assetId)){    
                    assetIdToBeQueried.add(ar.assetId);
                    actualAssetIds.add(ar.assetId);
                    allAssetRelationships.add(ar);
                }
                if (!actualAssetIds.contains(ar.relatedAssetId)) {
                    assetIdToBeQueried.add(ar.relatedAssetId);
                    actualAssetIds.add(ar.relatedAssetId);
                    allAssetRelationships.add(ar);
                }
            }
        }
    }

    /*
    * Validates the depth size of the bundle, e.g. the number of nested layers. This validation assumes every asset in the bundle contains the same groupingKey.
    */
    private static void validateBundleDepth(String groupingKey) {
        List<Asset> rootAssets;
        if (Schema.sObjectType.Asset.isAccessible()) {
            // Get root asset(s) of the bundle
            rootAssets = [SELECT name, Id FROM Asset WHERE Id IN (SELECT AssetId FROM AssetRelationship WHERE groupingKey = :groupingKey) AND Id NOT IN (SELECT RelatedAssetId FROM AssetRelationship WHERE groupingKey = :groupingKey)];
        } else {
            throw new CustomException('Cannot access the Asset entity, check your permissions.');
        }
        Set<String> rootAssetIds = new Set<String>();
        for (Asset asset : rootAssets) {
            rootAssetIds.add(asset.id);
        }

        if (rootAssetIds.size() > 1) {
            ValidationResults.errorMessages.add('There exists more than one AssetRelationship record that denotes a root asset: ' + rootAssetIds);
        }

        // Loop through the allowed number of times to see if assets exist for the i-th depth
        Set<String> assetsAtSpecificDepth = rootAssetIds;
        for (Integer i = 0; i < AssetValidatorConstants.MAX_BUNDLE_DEPTH; i++) {
            assetsAtSpecificDepth = getRelatedAssetIds(assetsAtSpecificDepth);
            // No assets exist at the i-th level, so no need to process the next level
            if (assetsAtSpecificDepth.isEmpty()) {
                break;
            }
        }

        if (!assetsAtSpecificDepth.isEmpty()) {
            ValidationResults.errorMessages.add('The depth of this bundle is more than the maximum allowed depth of ' + AssetValidatorConstants.MAX_BUNDLE_DEPTH);
        }
    }

    /**
    * Validates the same groupingKey is used for all AssetRelationship records
    */
    private static void validateGroupingKeys(List<AssetRelationship> allAssetRelationships) {  
        String referenceGroupingKey = allAssetRelationships.get(0).groupingKey;
        for (AssetRelationship ar : allAssetRelationships) {
            if (ar.groupingKey == null) {
                throw new CustomException('This bundle contains a missing groupingKey. Every AssetRelationship record in this bundle must have a groupingKey.');
            }
            if (ar.groupingKey != referenceGroupingKey) {
                throw new CustomException('This bundle contains more than one unique groupingKey. Only one unique groupingKey value can exist for a bundle.');
            }
        }
        ValidationResults.successMessages.add('All AssetRelationship records share the same groupingKey.');
    } 

    /**
    * Loops through every AssetRelationship and validates the AssetRelationship fields.
    */
    private static void validateFields(List<AssetRelationship> allAssetRelationships, Map<String, Asset> assetIdToAsset) {
        Set<String> uniqueRelatedAssetIds = new Set<String>();
        List<String> multiplePrimaryRelationship = new List<String>();
        List<String> missingAssetRole = new List<String>();
        List<String> missingRelatedRole = new List<String>();
        List<String> missingProductRelationshipType = new List<String>();
        List<String> incorrectFromDate = new List<String>();

        for (AssetRelationship ar : allAssetRelationships) {
            Asset parentAsset = assetIdToAsset.get(ar.AssetId);
            Asset childAsset = assetIdToAsset.get(ar.RelatedAssetId);

            // Validate that the FromDate is the latest of the Asset and RelatedAsset LifecycleStartDates
            Datetime latestFromDate = parentAsset.lifecycleStartDate > childAsset.lifecycleStartDate ? parentAsset.lifecycleStartDate : childAsset.lifecycleStartDate;
            if (ar.fromDate != latestFromDate) {
                incorrectFromDate.add(ar.Id);
            }

            // Validate that the RelatedAssetId doesn't appear more than once in the bundle            
            if (uniqueRelatedAssetIds.contains(ar.relatedAssetId)) {
                multiplePrimaryRelationship.add(ar.relatedAssetId);
            }
            else {
                uniqueRelatedAssetIds.add(ar.relatedAssetId);
            }

            // Validate that the AssetRole is set
            if (ar.assetRole == null) {
                missingAssetRole.add(ar.Id);
            }
            // Validate that the RelatedAssetRole is set
            if (ar.relatedassetrole == null) {
                missingRelatedRole.add(ar.Id);
            }
            // Validate that the ProductRelationshipTypeId is set
            if (ar.productRelationshipTypeId == null) {
                missingProductRelationshipType.add(ar.Id);
            }
        }

        processIdList(missingAssetRole, 'AssetRole');
        processIdList(missingRelatedRole, 'RelatedAssetRole');
        processIdList(missingProductRelationshipType, 'ProductRelationshipType');
        processIdList(incorrectFromDate, 'FromDate');

        if (missingAssetRole.isEmpty() && missingRelatedRole.isEmpty() && missingProductRelationshipType.isEmpty() && incorrectFromDate.isEmpty()) {
            ValidationResults.successMessages.add('All AssetRelationship field validations are successful.');
        }

        if (!multiplePrimaryRelationship.isEmpty()) {
            ValidationResults.errorMessages.add('The following assets have more than one primary asset: ' + multiplePrimaryRelationship + '. Only one primary relationship can exist for an asset');
        }
        else {
            ValidationResults.successMessages.add('All AssetRelationship records contain one primary asset.');
        }
    }

    /**
    * Logs an error if the list of entity ids is empty.
    */
    private static void processIdList(List<String> ids, String fieldName) {
        if (!ids.isEmpty()) {
            ValidationResults.errorMessages.add('The following AssetRelationship records have a missing or incorrect ' + fieldName + ': ' + ids);
        }
    }

    /**
    * Validates that the size of the bundle structure is within the allowed limits.
    */
    private static void validateBundleSize(List<AssetRelationship> allAssetRelationships) {
        // The number of assets is equal to the size of the asset bundle, plus the root asset
        Integer numberOfAssets = allAssetRelationships.size() + 1;

        if (numberOfAssets > AssetValidatorConstants.MAX_BUNDLE_SIZE) {
            ValidationResults.errorMessages.add('The number of assets (' + numberOfAssets + ') in this bundle exceeds the maximum allowed asset size of ' + AssetValidatorConstants.MAX_BUNDLE_SIZE);
        }
        else {
            ValidationResults.successMessages.add('The number of assets (' + numberOfAssets + ') is within the maximum allowed asset size of ' + AssetValidatorConstants.MAX_BUNDLE_SIZE);
        }
    }

    /**
    * Returns a list of related assets for a list of primary assets.
    */
    private static Set<String> getRelatedAssetIds(Set<String> assetIds) {
        Set<String> relatedAssetIds = new Set<String>();
        List<AssetRelationship> assetRelationships;
        if (Schema.sObjectType.AssetRelationship.isAccessible()) {
            assetRelationships = [SELECT relatedAssetId FROM assetRelationship WHERE assetId IN :assetIds];
        }  else {
            throw new CustomException('Cannot access the AssetRelationship entity, check your permissions');
        }

        for (AssetRelationship ar : assetRelationships) {
            relatedAssetIds.add(ar.relatedAssetId);
        }

        return relatedAssetIds;
    }

    /*
    * Queries for Assets in the set and returns a hashmap of an AssetId and its corresponding Asset.
    */
    private static Map<String, Asset> getAssetIdToAsset(Set<String> assetIds) {
        List<Asset> allAssets;
        if (Schema.sObjectType.Asset.isAccessible()) {
            allAssets = [SELECT Id, lifecycleStartDate FROM Asset WHERE Id IN :assetIds];
        } else {
            throw new CustomException('Cannot access the Asset entity, check your permissions.');
        }
        Map<String, Asset> assetIdToAsset = new Map<String, Asset>();

        for (Asset asset : allAssets) {
            assetIdToAsset.put(asset.Id, asset);
        }

        return assetIdToAsset;
    }
}