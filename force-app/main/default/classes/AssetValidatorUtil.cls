/**
 * Helper class to provide utils for Asset Validation
 *
 * @author rev volans
 * @since 246
 */
public with sharing class AssetValidatorUtil {

    // Checks for invalid Asset Ids provided by user
    public static Asset getAssetForAssetId(Id assetId) {
        System.debug('AssetId : ' + assetId);
        Asset asset = null;
        if (Schema.sObjectType.Asset.isAccessible()) {
            try {
                // Query the asset record from the database and SOQL will throw Exception if record not found
                asset = [SELECT Id, Name, Product2Id, HasLifecycleManagement, lifecycleStartDate, lifecycleEndDate, currentLifecycleEndDate, totalLifecycleAmount FROM Asset WHERE Id = :assetId];
            } catch(Exception e) {
                // Handles all cases where the query returned an empty or null result set
                System.debug('An error occurred while querying the Asset record: ' +  e.getMessage());
                throw new CustomException('An error occurred while querying the Asset record, please provide valid Asset id');
            }
        } else {
            throw new CustomException('Insufficient access to Asset entity');
        }
        
        // We will never return null asset, we will always throw exception for null records
        return asset;
    }

  
    // Validates Input fields for Assets
    public static void validateAssetInputFields(Asset asset) {
        List<String> errorResults = new List<String>();
        if(asset.Product2Id == null) {
            errorResults.add('ProductId is required field, please provide a valid ProductId');
        }
        if(!asset.HasLifecycleManagement) {
            errorResults.add('Lifecycle-managed asset checkbox should be set to true');
        }
        if(errorResults.isEmpty()) {
            ValidationResults.successMessages.add('Assets fields are valid');
        } else {
            ValidationResults.errorMessages.addAll(errorResults);
        }
    }
   
    
    // Validate AssetStatePeriods and Assets Lifecycle start and end dates.
    public static void validateASPandLifecycleDates(Asset asset, List<AssetStatePeriod> asps) {
        validateASPDatesForGapAndOverlap(asps);
        validateAssetLifecycleDates(asps, asset.lifecycleStartDate, asset.lifecycleEndDate);
        validateASPDatesForCPQPlusOrBilling(asps);
        validateAssetCurrentLifecycleEndDate(asps, asset.currentLifecycleEndDate);
    }

    // Validate Assets currentLifecycleEndDate for cron job
    public static void validateAssetCurrentLifecycleEndDate(List<AssetStatePeriod> asps, Datetime currentLifecycleEndDate) {
        String errorResult = null;
        DateTime currentDate = Datetime.now();

        // For future Asset
        if(asps[0].startDate > currentDate && currentLifecycleEndDate != (asps[0].startDate.addSeconds(-1))) {
            errorResult = 'Assets currentLifecycleEndDate should be 1 second earlier than Asset lifecycle start date i.e. :' + (asps[0].startDate.addSeconds(-1));
        }

        // For past Asset
        if(asps[asps.size()-1].endDate < currentDate && currentLifecycleEndDate != null) {
            errorResult = 'For expired Assets currentLifecycleEndDate should not be set';  
        }

        // For ongoing Asset 
        for(AssetStatePeriod asp : asps) {
            if(asp.startDate <= currentDate && (asp.endDate == null || asp.endDate >= currentDate)) {
                if(currentLifecycleEndDate != asp.endDate) {
                    errorResult = 'Assets currentLifecycleEndDate should be same as end date of ongoing ASP Id :' + asp.id;
                }
            }
        }
        if (errorResult == null) {
            ValidationResults.successMessages.add('Assets currentLifecycleEndDate is valid');
        } else {
            ValidationResults.errorMessages.add(errorResult);
        }
    }
    
    // Validate Asset action for given asset Id according to LifecycleManagement standards
    public static void validateAssetActionsForCPQPlusOrBilling(List<AssetAction> assetActions) {
        List<String> errorResults = validateAAFields(assetActions);
        if(errorResults.isEmpty()) {
            ValidationResults.successMessages.add('AssetActions are valid for given Asset Id');
        } else {
            ValidationResults.errorMessages.addAll(errorResults);
        }
    }
    
    // Validate Asset action sources for given asset Id
    public static void validateAssetActionSourcesForCPQPlusOrBilling(List<AssetActionSource> assetActionSources) {
        List<String> errorResults = new List<String>();
        for(AssetActionSource aas:assetActionSources) {
            if((aas.ExternalReference == null || aas.ExternalReferenceDataSource == null) && aas.ReferenceEntityItemId == null) {
                errorResults.add('AssetActionSource should have reference for Id:' + aas.Id);
            }
        }
        if(assetActionSources.isEmpty()) {
            ValidationResults.successMessages.add('No AssetActionSources available for this Asset');
        } else if (errorResults.isEmpty()) {
            ValidationResults.successMessages.add('AssetActionSources are valid for the given Asset Id');
        } else {
            ValidationResults.errorMessages.addAll(errorResults);
        }
    }

    // Validates ASP fields and date formats according to SubscriptionManagement standard
    public static void validateASPForSubMgmt(Asset asset, List<AssetStatePeriod> asps) {
        validateASPDatesForGapAndOverlap(asps);
        validateAssetLifecycleDates(asps, asset.lifecycleStartDate, asset.lifecycleEndDate);
        validateASPDatesForSM(asps);
        validateASPQtyAndMrr(asps);
        validateAssetCurrentLifecycleEndDate(asps, asset.currentLifecycleEndDate);
    }

    // Validates AAS and AA fields for a given asset according to SubscriptionManagement standard
    public static void validateAASAndAAForSubMgmt(List<AssetAction> assetActions, List<AssetActionSource> assetActionSources) {
        List<String> errorResults = validateAAFields(assetActions);
        List<String> absentAASViolations = validateAASExistsForAA(assetActions, assetActionSources);
        List<String> invalidReferenceEntityItemIds = validateAASReferenceEntityItem(assetActionSources);
        if (absentAASViolations.size() > 0) {
            errorResults.add('Each AssetAction should have at least one associated AssetActionSource, found no AssetActionSource for AssetAction(s): ' + absentAASViolations);
        }
        if (invalidReferenceEntityItemIds.size() > 0) {
            errorResults.add('AssetActionSource should have a valid ReferenceEntityItemId set, please check AssetActionSource Id(s): ' + invalidReferenceEntityItemIds);
        }
        if (errorResults.isEmpty()) {
            ValidationResults.successMessages.add('AssetAction(s) and AssetActionSource(s) are valid for the given Asset Id');
        } else {
            ValidationResults.errorMessages.addAll(errorResults);
        }
    }

    // Validates that the total lifecycle amount for an asset matches the sum of amount from all asset actions
    public static void validateTotalLifecycleAmount(Asset asset, List<AssetAction> assetActions) {
        Double totalAmountFromAA = 0.0;
        for (AssetAction aa: assetActions) {
            totalAmountFromAA += aa.Amount;
        }
        if (totalAmountFromAA != Double.valueOf(asset.totalLifecycleAmount)) {
            ValidationResults.errorMessages.add('Asset.totalLifecycleAmount doesn\'t match the sum of all associated AssetAction for asset Id: ' + asset.Id);
        } else {
            ValidationResults.successMessages.add('Asset.totalLifecycleAmount is valid');
        }
    }

    // Query AssetStatePeriod records from the database
    public static List<AssetStatePeriod> queryASPs(Id assetId) {
        List<AssetStatePeriod> asps;
        if (Schema.sObjectType.AssetStatePeriod.isAccessible()) {
            asps = [SELECT Id, startDate, endDate, quantity, mrr FROM AssetStatePeriod WHERE assetId = :assetId ORDER BY StartDate ASC];
        } else {
            throw new CustomException('Insufficient access to AssetStatePeriod entity');
        }
        if(asps.isEmpty()) {
            throw new CustomException('Lifecycle Managed Assets must have related AssetStatePeriod Entity');
        }
        return asps;
    }
    
    // Query AssetAction records from the database
    public static List<AssetAction> queryAAs(Id assetId) {
        List<AssetAction> assetActions;
        if (Schema.sObjectType.AssetAction.isAccessible()) {
            assetActions = [SELECT Id, CategoryEnum, ActionDate, Amount FROM AssetAction WHERE assetId = :assetId ORDER BY ActionDate ASC];
        } else {
            throw new CustomException('Insufficient access to AssetAction entity');
        }
        if(assetActions.isEmpty()) {
            throw new CustomException('Lifecycle Managed Assets must have related AssetAction Entity');
        }
        return assetActions;
    }

    // Query AssetActionSource records from the database
    public static List<AssetActionSource> queryAASs(Id assetId) {
        List<AssetActionSource> assetActionSources;
        if (Schema.sObjectType.AssetActionSource.isAccessible()) {
            assetActionSources = [SELECT Id, ReferenceEntityItemId, ExternalReference, ExternalReferenceDataSource, AssetActionId FROM AssetActionSource 
                                 WHERE AssetAction.AssetId = :assetId];
        } else {
            throw new CustomException('Insufficient access to AssetActionSource entity');
        }
        return assetActionSources;
    }
        
    // Validate that AssetStatePeriods does not have gaps or overlaps between them and For Evergreen Assets only last ASP.endDate can be null
    private static void validateASPDatesForGapAndOverlap(List<AssetStatePeriod> asps) {
        List<String> errorResults = new List<String>();
        AssetStatePeriod previousASP = null;
        Id lastASPId = asps[asps.size()-1].Id;
        List<String> results = new List<String>();
        for(AssetStatePeriod asp : asps) {
            // Store first ASP and skip it, since we do not need to verify gaps/overlaps for it.
            if(previousASP != null) {
                DateTime currentStartDate = asp.startDate;
                DateTime previousEndDate = previousASP.endDate;
                Long secondsDiff = (currentStartDate.getTime() - previousEndDate.getTime())/1000;
                if(secondsDiff > 1) {
                    errorResults.add('AssetstatePeriod with Id: ' + asp.Id + ' is not contiguous with previous AssetstatePeriod Id: ' + previousASP.Id);
                }
                if(secondsDiff < 1) {
                    errorResults.add('AssetstatePeriod with Id: ' + asp.Id + ' is overlapping with previous AssetstatePeriod Id: ' + previousASP.Id);
                }
            }
            if(asp.endDate == null && asp.Id != lastASPId) {
                throw new CustomException('Error: For Evergreen Assets only last AssetStatePeriods EndDate can be NULL. Please check ASP Id: ' + asp.Id);
            }
            previousASP = asp;
        }
        if(errorResults.isEmpty()) {
            ValidationResults.successMessages.add('AssetstatePeriods does not have Gaps or overlaps');
        } else {
            ValidationResults.errorMessages.addAll(errorResults);
        }
    }

    
    // Validates Asset LifecycleStartDate and LifecycleEndDate are aligned with AssetStatePeriod startDate and endDate
    private static void validateAssetLifecycleDates(List<AssetStatePeriod> asps, DateTime lifecycleStartDate, DateTime lifecycleEndDate) {
        List<String> errorResults = new List<String>();
        DateTime actualStartDate = asps[0].startDate;
        DateTime actualEndDate = asps[asps.size()-1].endDate;
        // Validate LifecycleStartDate
        if(lifecycleStartDate != null) {
            if (lifecycleStartDate != actualStartDate) {
                errorResults.add('lifecycleStartDate does not match with startDate of the first AssetStatePeriod.');
            }
            // Validate LifecycleEndDate should be after LifecycleStartDate 
            if(lifecycleEndDate != null && lifecycleStartDate > lifecycleEndDate) {
                errorResults.add('lifecycleStartDate should start before LifecycleEndDate. Please check Assets lifecycleStartDate and LifecycleEndDate');
            }  
        } else {
            errorResults.add('lifecycleStartDate should not be NULL.');
        }

        if(lifecycleEndDate != actualEndDate) {
            errorResults.add('LifecycleEndDate does not match with endDate of latest AssetStatePeriod');
        }
        if(errorResults.isEmpty()) {
            ValidationResults.successMessages.add('Asset LifecycleStartDate and LifecycleEndDate are valid');
        } else {
            ValidationResults.errorMessages.addAll(errorResults);
        }
    }

    
    // Validates date format for AssetStatePeriod start and end dates according to LifecycleManagemnt standards
    private static void validateASPDatesForCPQPlusOrBilling(List<AssetStatePeriod> asps) {
        List<String> errorResults = new List<String>();
        Id lastASPId = asps[asps.size()-1].Id;
        for(AssetStatePeriod asp : asps) {
            DateTime startDate = asp.StartDate;
            DateTime endDate = asp.EndDate;
            if(startDate.second() != 0) {
                errorResults.add('AssetStatePeriod startDate time should be 00 second. Please check ASP Id: ' + asp.Id);
            }
            // Evergreen ASP does not need these validations
            if(endDate != null) {
                if(startDate > endDate) {
                    errorResults.add('AssetStatePeriod startDate should be before endDate. Please check ASP Id: ' + asp.Id);
                }
                if(endDate.second() != 59) {
                    errorResults.add('AssetStatePeriod endDate time should be 59 seconds. Please check ASP Id: ' + asp.Id);
                }
                Long secondsDiff = (endDate.getTime() - startDate.getTime())/1000;
                if(Math.mod(secondsDiff+1,86400) != 0) {
                    errorResults.add('AssetStatePeriod must span for multiples of 24 hours. Please check ASP Id: ' + asp.Id);
                }
            } 
        }
        
        if(errorResults.isEmpty()) {
            ValidationResults.successMessages.add('AssetstatePeriods Dates and Date formats are valid');
        } else {
            ValidationResults.errorMessages.addAll(errorResults);
        }
    }
    
    // Validates date format for AssetStatePeriod start and end dates according to SubscriptionManagement standards
    private static void validateASPDatesForSM(List<AssetStatePeriod> asps) {
        List<String> errorResults = new List<String>();
        Id lastASPId = asps[asps.size()-1].Id;
        for (AssetStatePeriod asp : asps) {
            DateTime startDate = asp.StartDate;
            DateTime endDate = asp.EndDate;
            if (startDate.second() != 0 || startDate.minute() != 0 || startDate.hourGmt() != 0) {
                errorResults.add('AssetStatePeriod must have a startDate with time formatted as 00:00:00 in UTC. Please check ASP Id: ' + asp.Id);
            }
            // Validate end date format for non-evergreen ASPs
            if (endDate != null) {
                if(startDate > endDate) {
                    errorResults.add('AssetStatePeriod startDate should be before endDate. Please check ASP Id: ' + asp.Id);
                }
                if (endDate.second() != 59 || asp.endDate.minute() != 59 || asp.endDate.hourGmt() != 23) {
                    errorResults.add('AssetStatePeriod must have an endDate with time formatted 23:59:59 in UTC. Please check ASP Id: ' + asp.Id);
                }
                Long secondsDiff = (endDate.getTime() - startDate.getTime()) / 1000;
                if (Math.mod(secondsDiff+1,86400) != 0) {
                    errorResults.add('AssetStatePeriod must span for multiples of 24 hours. Please check ASP Id: ' + asp.Id);
                }
            } 
        }
        
        if(errorResults.isEmpty()) {
            ValidationResults.successMessages.add('AssetstatePeriods Dates and Date formats are valid');
        } else {
            ValidationResults.errorMessages.addAll(errorResults);
        }
    }

    // Validates that each AA has at least 1 AAS given all AA and AAS associated to an asset
    private static List<String> validateAASExistsForAA(List<AssetAction> assetActions, List<AssetActionSource> assetActionSources) {
        List<String> absentAASViolations = new List<String>();
        Set<String> aaIdFromListOfAAS = new Set<String>();
        // Collect all AA.Id that has at least an associated AAS
        for (AssetActionSource aas:assetActionSources) {
            aaIdFromListOfAAS.add(aas.AssetActionId);
        }
        // Compare the list of AA with the set of AA collected from the list of AAS
        for (AssetAction assetAction:assetActions) {
            if (!aaIdFromListOfAAS.contains(assetAction.Id)) {
                absentAASViolations.add(assetAction.Id);
            }
        }
        return absentAASViolations;
    }

    // Validates all AssetActionSource(s) have valid ReferenceEntityItemId(s) populated
    private static List<String> validateAASReferenceEntityItem(List<AssetActionSource> assetActionSources) {
        List<String> invalidReferenceEntityItemIds = new List<String>();
        Set<String> referenceEntityItemIds = new Set<String>();
        // Collect all non-null ReferenceEntityItemIds to be queried and verified
        for (AssetActionSource aas:assetActionSources) {
            if (aas.ReferenceEntityItemId == null) {
                invalidReferenceEntityItemIds.add(aas.Id);
            } else {
                referenceEntityItemIds.add(aas.ReferenceEntityItemId);
            }
        }
        Set<String> orderItemIds = new Set<String>();
        if (Schema.sObjectType.OrderItem.isAccessible()) {
            try {
                List<OrderItem> orderItems = [SELECT Id FROM OrderItem WHERE Id in :referenceEntityItemIds];
                for (OrderItem oi: orderItems) {
                    orderItemIds.add(oi.Id);
                }
            } catch (Exception e) {
                // Swallow the error so that verifications can be continued
                System.debug('An error occurred while querying the OrderItem record: ' +  e.getMessage());
            }
        } else {
            throw new CustomException('Insufficient access to OrderItem entity');
        }

        // Validate that each referenceEntityItemId is a valid OrderItemId
        for (AssetActionSource aas:assetActionSources) {
            if (aas.ReferenceEntityItemId != null && !orderItemIds.contains(aas.ReferenceEntityItemId)) {
                invalidReferenceEntityItemIds.add(aas.Id);
            }
        }
        return invalidReferenceEntityItemIds;
    }

    // Validates AssetAction fields
    private static List<String> validateAAFields(List<AssetAction> assetActions) {
        List<String> errorResults = new List<String>();
        AssetAction previousAssetAction = null;
        Set<DateTime> seenAssetActionDates = new Set<DateTime>();
        for(AssetAction aa:assetActions) {
            if(aa.CategoryEnum == null) {
                errorResults.add('AssetAction must have BusinessCategory field populated for Id: ' + aa.Id);
            }
            if(previousAssetAction != null && previousAssetAction.ActionDate != null && seenAssetActionDates.contains(aa.ActionDate)) {
                errorResults.add('AssetAction actionDates should be unique. Please check AssetAction Id: ' + aa.Id);
            }
            previousAssetAction = aa;
            seenAssetActionDates.add(aa.ActionDate);
        }
        return errorResults;
    }

    // Validates quantity and mrr for AssetStatePeriod(s)
    private static void validateASPQtyAndMrr(List<AssetStatePeriod> asps) {
        List<String> errorResults = new List<String>();
        List<String> quantityViolations = new List<String>();
        List<String> mrrViolations = new List<String>();
        for (AssetStatePeriod asp : asps) {
            if (asp.quantity < 0) {
                quantityViolations.add(asp.Id);
            }
            if (asp.mrr < 0) {
                mrrViolations.add(asp.Id);
            }
        }
        if (quantityViolations.size() > 0) {
            errorResults.add('AssetStatePeriod must have a non-negative quantity. Please check ASP Id(s): ' + quantityViolations);
        }
        if (mrrViolations.size() > 0) {
            errorResults.add('AssetStatePeriod must have a non-negative mrr. Please check ASP Id: ' + mrrViolations);
        }
        if (errorResults.isEmpty()) {
            ValidationResults.successMessages.add('Quantity and mrr for all AssetStatePeriods are valid');
        } else {
            ValidationResults.errorMessages.addAll(errorResults);
        }
    }
}
