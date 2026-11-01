/**
 * Replaces personal data in a Shopify webhook payload with fixed dummy values
 * and reports any original personal value still present in the result.
 */

// Replacement per JSON key. Null values in the payload stay null.
const REPLACEMENTS = {
    email: 'jane.doe@example.com',
    contact_email: 'jane.doe@example.com',
    customer_email: 'jane.doe@example.com',
    first_name: 'Jane',
    last_name: 'Doe',
    phone: '+15555550100',
    address1: '123 Main St',
    address2: null,
    city: 'Springfield',
    zip: '62701',
    province: 'Illinois',
    province_code: 'IL',
    company: null,
    latitude: null,
    longitude: null,
    browser_ip: '203.0.113.10',
    client_ip: '203.0.113.10',
    user_agent: 'Mozilla/5.0',
    token: '0000',
    cart_token: null,
    checkout_token: '0000',
    order_status_url: 'https://example.com/orders/0000/authenticate?key=0000',
    landing_site: null,
    landing_site_ref: null,
    referring_site: null,
    confirmation_number: 'TESTCONF1',
    note: null
};

// Inside these objects, `name` is a person's name rather than a product or order name
const PERSON_OBJECTS = new Set(['billing_address', 'shipping_address', 'default_address', 'addresses', 'customer']);

// Keys holding a person's name; their parts (e.g. a first name on its own) are searched for too
const NAME_KEYS = new Set(['first_name', 'last_name', 'name']);

// Original values shorter than this are too generic to search for (e.g. "US")
const MIN_LEAK_LENGTH = 3;

function escapeRegExp(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function anonymize(payload) {
    const originals = new Set();
    const remember = (key, value) => {
        if (typeof value !== 'string' || value.trim().length < MIN_LEAK_LENGTH) {
            return;
        }
        originals.add(value.trim());
        if (NAME_KEYS.has(key)) {
            value
                .split(/\s+/)
                .filter((part) => part.length >= MIN_LEAK_LENGTH)
                .forEach((part) => originals.add(part));
        }
    };

    const walk = (node, inPerson) => {
        if (Array.isArray(node)) {
            node.forEach((item) => walk(item, inPerson));
            return;
        }
        if (!node || typeof node !== 'object') {
            return;
        }
        for (const key of Object.keys(node)) {
            const value = node[key];
            if (value && typeof value === 'object') {
                walk(value, inPerson || PERSON_OBJECTS.has(key));
            } else if (key in REPLACEMENTS && value !== null) {
                remember(key, value);
                node[key] = REPLACEMENTS[key];
            } else if (key === 'name' && inPerson && value !== null) {
                remember(key, value);
                node[key] = 'Jane Doe';
            }
        }
    };

    const copy = JSON.parse(JSON.stringify(payload));
    walk(copy, false);
    const output = JSON.stringify(copy, null, 2);

    // Words used by the dummy values themselves (e.g. "123" in "123 Main St") are not leaks
    const replacementWords = new Set(
        Object.values(REPLACEMENTS)
            .filter(Boolean)
            .flatMap((v) => [String(v), ...String(v).split(/\s+/)])
            .map((v) => v.toLowerCase())
    );
    // Whole words only, so "Los" does not match "closed_at" and a zip code does not match inside a long ID
    const isPresent = (value) =>
        new RegExp('(^|[^\\p{L}\\p{N}])' + escapeRegExp(value) + '($|[^\\p{L}\\p{N}])', 'iu').test(output);
    const leaks = [...originals].filter((value) => !replacementWords.has(value.toLowerCase()) && isPresent(value));
    const foreignEmails = (output.match(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g) || []).filter(
        (email) => !/@example\.com$/i.test(email)
    );

    return { output: output + '\n', leaks, foreignEmails };
}

module.exports = { anonymize };
