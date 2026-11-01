#!/usr/bin/env node
// Deploys this project to the orderhub org and summarizes tests and coverage. See SKILL.md.
const fs = require('fs');
const path = require('path');
const { TARGET_ORG, PROJECT_DIR, sf } = require('../../lib/sf');

const COVERAGE_TARGET = 90;

function parseArgs(argv) {
    const options = { dryRun: false, tests: [], noTests: false, sourceDir: 'force-app' };
    for (let i = 0; i < argv.length; i++) {
        const arg = argv[i];
        if (arg === '--dry-run') {
            options.dryRun = true;
        } else if (arg === '--no-tests') {
            options.noTests = true;
        } else if (arg === '--tests') {
            options.tests = (argv[++i] || '')
                .split(',')
                .map((name) => name.trim())
                .filter(Boolean);
        } else if (arg === '--path') {
            options.sourceDir = argv[++i];
        } else {
            throw new Error(`Unknown option: ${arg}`);
        }
    }
    if (options.noTests && options.tests.length) {
        throw new Error('--tests and --no-tests cannot be combined.');
    }
    return options;
}

function localClassNames() {
    const dir = path.join(PROJECT_DIR, 'force-app', 'main', 'default', 'classes');
    const triggers = path.join(PROJECT_DIR, 'force-app', 'main', 'default', 'triggers');
    const names = (folder, ext) =>
        fs.existsSync(folder)
            ? fs
                  .readdirSync(folder)
                  .filter((f) => f.endsWith(ext))
                  .map((f) => f.slice(0, -ext.length))
            : [];
    return new Set([...names(dir, '.cls'), ...names(triggers, '.trigger')]);
}

const asList = (value) => (value === undefined || value === null ? [] : [].concat(value));

function main() {
    const options = parseArgs(process.argv.slice(2));
    const args = ['project', 'deploy', 'start', '--source-dir', options.sourceDir, '--wait', '30'];
    if (options.dryRun) {
        args.push('--dry-run');
    }
    if (options.noTests) {
        args.push('--test-level', 'NoTestRun');
    } else if (options.tests.length) {
        args.push('--test-level', 'RunSpecifiedTests');
        options.tests.forEach((name) => args.push('--tests', name));
    } else {
        args.push('--test-level', 'RunLocalTests');
    }

    console.log(`${options.dryRun ? 'Validating' : 'Deploying'} ${options.sourceDir} to ${TARGET_ORG}...`);
    const response = sf(args);
    const result = response.result || {};
    const details = result.details || {};
    const testResult = details.runTestResult || {};

    const status = result.status || response.name || 'Failed';
    console.log(`\nStatus: ${status}${options.dryRun ? ' (dry run, nothing saved)' : ''}`);
    if (!result.status && response.message) {
        console.log(`Error: ${response.message}`);
    }
    console.log(`Components: ${result.numberComponentsDeployed ?? 0}/${result.numberComponentsTotal ?? 0}`);
    if (!options.noTests) {
        console.log(`Tests: ${result.numberTestsCompleted ?? 0}/${result.numberTestsTotal ?? 0} passed`);
    }

    const componentFailures = asList(details.componentFailures);
    if (componentFailures.length) {
        console.log('\nComponent failures:');
        componentFailures.forEach((f) =>
            console.log(
                `  ${f.componentType} ${f.fullName} (${f.lineNumber ?? '-'}:${f.columnNumber ?? '-'}): ${f.problem}`
            )
        );
    }

    const testFailures = asList(testResult.failures);
    if (testFailures.length) {
        console.log('\nTest failures:');
        testFailures.forEach((f) => {
            console.log(`  ${f.name}.${f.methodName}: ${f.message}`);
            const firstLine = (f.stackTrace || '').split('\n')[0];
            if (firstLine) {
                console.log(`    at ${firstLine}`);
            }
        });
    }

    const ownCode = localClassNames();
    const coverage = asList(testResult.codeCoverage)
        .filter((c) => ownCode.has(c.name) && c.numLocations > 0)
        .map((c) => ({ name: c.name, percent: Math.round(100 - (100 * c.numLocationsNotCovered) / c.numLocations) }))
        .sort((a, b) => a.percent - b.percent || a.name.localeCompare(b.name));
    if (coverage.length) {
        console.log('\nCoverage:');
        coverage.forEach((c) =>
            console.log(
                `  ${String(c.percent).padStart(3)}%  ${c.name}${c.percent < COVERAGE_TARGET ? '  <-- below ' + COVERAGE_TARGET + '%' : ''}`
            )
        );
    }

    process.exit(status === 'Succeeded' ? 0 : 1);
}

try {
    main();
} catch (error) {
    console.error(error.message);
    process.exit(1);
}
