#!/usr/bin/env node
// Saves an anonymized Shopify payload from a Sync_Log__c as a static resource. See SKILL.md.
const fs = require('fs');
const path = require('path');
const { PROJECT_DIR, query } = require('../../lib/sf');
const { anonymize } = require('./anonymize');

function parseArgs(argv) {
    const [logName, resourceName, ...rest] = argv;
    if (!/^LOG-\d+$/.test(logName || '') || !/^[A-Za-z][A-Za-z0-9_]*$/.test(resourceName || '')) {
        throw new Error('Usage: capture-fixture.js <LOG-name> <ResourceName> [--description "..."] [--force]');
    }
    const options = { logName, resourceName, force: false, description: null };
    for (let i = 0; i < rest.length; i++) {
        if (rest[i] === '--force') {
            options.force = true;
        } else if (rest[i] === '--description') {
            options.description = rest[++i];
        } else {
            throw new Error(`Unknown option: ${rest[i]}`);
        }
    }
    return options;
}

function escapeXml(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function main() {
    const options = parseArgs(process.argv.slice(2));
    const [log] = query(`SELECT Event_Topic__c, Payload__c FROM Sync_Log__c WHERE Name = '${options.logName}'`);
    if (!log) {
        throw new Error(`${options.logName} not found.`);
    }
    if (!log.Payload__c) {
        throw new Error(`${options.logName} has no stored payload.`);
    }

    let payload;
    try {
        payload = JSON.parse(log.Payload__c);
    } catch {
        throw new Error(`${options.logName} payload is not valid JSON (it may have been truncated).`);
    }

    const { output, leaks, foreignEmails } = anonymize(payload);
    if (leaks.length || foreignEmails.length) {
        console.error('Refusing to write the fixture: personal data is still present.');
        leaks.forEach((value) => console.error(`  original value still present: "${value}"`));
        foreignEmails.forEach((email) => console.error(`  email outside example.com: ${email}`));
        console.error('Extend the rules in .claude/skills/capture-fixture/anonymize.js and run again.');
        process.exit(1);
    }

    const dir = path.join(PROJECT_DIR, 'force-app', 'main', 'default', 'staticresources');
    const jsonFile = path.join(dir, `${options.resourceName}.json`);
    const metaFile = path.join(dir, `${options.resourceName}.resource-meta.xml`);
    if (!options.force && (fs.existsSync(jsonFile) || fs.existsSync(metaFile))) {
        throw new Error(`${options.resourceName} already exists. Pass --force to overwrite it.`);
    }

    const description =
        options.description ||
        `Anonymized ${log.Event_Topic__c || 'Shopify'} webhook payload from the dev store, used by Apex tests.`;
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(jsonFile, output);
    fs.writeFileSync(
        metaFile,
        [
            '<?xml version="1.0" encoding="UTF-8"?>',
            '<StaticResource xmlns="http://soap.sforce.com/2006/04/metadata">',
            '    <cacheControl>Private</cacheControl>',
            '    <contentType>application/json</contentType>',
            `    <description>${escapeXml(description)}</description>`,
            '</StaticResource>',
            ''
        ].join('\n')
    );

    console.log(`Wrote ${path.relative(PROJECT_DIR, jsonFile)} (${output.length} characters) and its meta file.`);
    console.log(
        `Source: ${options.logName}, topic ${log.Event_Topic__c || '-'}. No personal values found in the output.`
    );
    console.log('Next: skim the JSON for free-text personal data, then deploy the static resource.');
}

try {
    main();
} catch (error) {
    console.error(error.message);
    process.exit(1);
}
