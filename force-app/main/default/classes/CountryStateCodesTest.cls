// Relies on the United States, Canada and Australia states being enabled, as they are by default
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
    static void acceptsCodeThatExistsInSeveralCountries() {
        Assert.isTrue(CountryStateCodes.isValidState('US', 'WA'), 'Washington');
        Assert.isTrue(CountryStateCodes.isValidState('US', 'CA'), 'California');
        Assert.isTrue(CountryStateCodes.isValidState('AU', 'WA'), 'Western Australia');
    }

    @IsTest
    static void acceptsEveryUsState() {
        List<String> usStates = ('AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ ' +
            'NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY')
            .split(' ');
        for (String state : usStates) {
            Assert.isTrue(CountryStateCodes.isValidState('US', state), state);
        }
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
