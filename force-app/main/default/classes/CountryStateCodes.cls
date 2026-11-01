/**
 * Country and state codes enabled in the org's State and Country/Territory Picklists.
 * Writing a code the org does not know fails the whole DML statement, so callers
 * check codes from external systems before setting them.
 */
public with sharing class CountryStateCodes {
    // Position of each active country in the country picklist, which validFor bitmaps refer to
    private static Map<String, Integer> indexByCountryCode;
    // Not keyed by code: many codes exist in several countries (e.g. WA for Washington and Western Australia)
    private static List<StateEntry> stateEntries;
    private static final Map<String, Set<String>> STATE_CODES_BY_COUNTRY = new Map<String, Set<String>>();

    private class StateEntry {
        final String code;
        final String validForHex;

        StateEntry(String code, String validForHex) {
            this.code = code;
            this.validForHex = validForHex;
        }
    }

    public static Boolean isValidCountry(String countryCode) {
        return countryCode != null && countryIndexes().containsKey(countryCode);
    }

    /**
     * True when the state code is enabled for that country; states depend on the country picklist.
     */
    public static Boolean isValidState(String countryCode, String stateCode) {
        return stateCode != null && isValidCountry(countryCode) && stateCodes(countryCode).contains(stateCode);
    }

    private static Map<String, Integer> countryIndexes() {
        if (indexByCountryCode == null) {
            List<Schema.PicklistEntry> entries = Order.BillingCountryCode.getDescribe().getPicklistValues();
            indexByCountryCode = new Map<String, Integer>();
            for (Integer i = 0; i < entries.size(); i++) {
                if (entries[i].isActive()) {
                    indexByCountryCode.put(entries[i].getValue(), i);
                }
            }
        }
        return indexByCountryCode;
    }

    // A state's validFor is a bitmap over the country entries: bit i set means valid for country i
    private static Set<String> stateCodes(String countryCode) {
        if (!STATE_CODES_BY_COUNTRY.containsKey(countryCode)) {
            Integer countryIndex = countryIndexes().get(countryCode);
            Set<String> codes = new Set<String>();
            for (StateEntry state : stateEntries()) {
                if (isBitSet(state.validForHex, countryIndex)) {
                    codes.add(state.code);
                }
            }
            STATE_CODES_BY_COUNTRY.put(countryCode, codes);
        }
        return STATE_CODES_BY_COUNTRY.get(countryCode);
    }

    // PicklistEntry exposes validFor only through its JSON form
    private static List<StateEntry> stateEntries() {
        if (stateEntries == null) {
            stateEntries = new List<StateEntry>();
            for (Schema.PicklistEntry entry : Order.BillingStateCode.getDescribe().getPicklistValues()) {
                Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(entry));
                String validFor = (String) raw.get('validFor');
                if (entry.isActive() && String.isNotBlank(validFor)) {
                    stateEntries.add(
                        new StateEntry(entry.getValue(), EncodingUtil.convertToHex(EncodingUtil.base64Decode(validFor)))
                    );
                }
            }
        }
        return stateEntries;
    }

    // Bits are numbered from the most significant bit of the first byte, i.e. of the first hex digit
    private static Boolean isBitSet(String hex, Integer index) {
        if (index / 4 >= hex.length()) {
            return false;
        }
        Integer nibble = hexDigitValue(hex.charAt(index / 4));
        return (nibble & (8 >> Math.mod(index, 4))) != 0;
    }

    private static Integer hexDigitValue(Integer charCode) {
        // '0'-'9' are 48-57, 'a'-'f' are 97-102 (convertToHex returns lower case)
        return charCode <= 57 ? charCode - 48 : charCode - 87;
    }
}
