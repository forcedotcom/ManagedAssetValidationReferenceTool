/**
 * Helper class to store validation results for asset validation
 *
 * @author rev volans
 * @since 246
 */
public with sharing class ValidationResults {

    public static List<String> successMessages = new List<String>();

    public static List<String> errorMessages = new List<String>();

    public static void clearResults() {
        successMessages = new List<String>();
        errorMessages = new List<String>();
    }
}