// Relies on the United States and Canada states being enabled, as they are by default
@IsTest
private class CountryStateCodesTest {
    @IsTest
    static void acceptsEnabledCountry() {
        Assert.isTrue(CountryStateCodes.isValidCountry('US'));
        Assert.isTrue(CountryStateCodes.isValidCountry('CA'));
    }

    @IsTest
    static void rejectsUnknownOrMissingCountry() {
        Assert.isFalse(CountryStateCodes.isValidCountry('XX'));
        Assert.isFalse(CountryStateCodes.isValidCountry(null));
    }

    @IsTest
    static void acceptsStateOfItsOwnCountry() {
        Assert.isTrue(CountryStateCodes.isValidState('US', 'IL'));
        Assert.isTrue(CountryStateCodes.isValidState('CA', 'ON'));
    }

    @IsTest
    static void rejectsStateOfAnotherCountry() {
        Assert.isFalse(CountryStateCodes.isValidState('US', 'ON'), 'Ontario is a Canadian province');
        Assert.isFalse(CountryStateCodes.isValidState('CA', 'IL'), 'Illinois is a US state');
    }

    @IsTest
    static void rejectsUnknownOrMissingState() {
        Assert.isFalse(CountryStateCodes.isValidState('US', 'XX'));
        Assert.isFalse(CountryStateCodes.isValidState('US', null));
        Assert.isFalse(CountryStateCodes.isValidState('XX', 'IL'));
        Assert.isFalse(CountryStateCodes.isValidState(null, 'IL'));
    }
}
