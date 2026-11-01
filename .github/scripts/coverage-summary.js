/**
 * Turns the CLI's json-summary coverage report into a Markdown table for the GitHub job summary.
 * Only lists Apex classes and triggers from force-app; the org also contains classes this
 * project does not own (e.g. the standard Site controllers).
 *
 * Usage: node coverage-summary.js <coverage-summary.json>
 */
const fs = require('fs');
const path = require('path');

const COVERAGE_TARGET = 90;
const SOURCE_DIRS = ['force-app/main/default/classes', 'force-app/main/default/triggers'];

function projectApexNames() {
    const names = new Set();
    for (const dir of SOURCE_DIRS) {
        const fullDir = path.resolve(__dirname, '..', '..', dir);
        if (!fs.existsSync(fullDir)) continue;
        fs.readdirSync(fullDir)
            .filter((file) => /\.(cls|trigger)$/.test(file))
            .forEach((file) => names.add(file.replace(/\.(cls|trigger)$/, '')));
    }
    return names;
}

const reportPath = process.argv[2];
if (!reportPath || !fs.existsSync(reportPath)) {
    console.log('### Apex coverage\n\nNo coverage report was produced (see the step log).');
    process.exit(0);
}

const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
const ownNames = projectApexNames();

// Keys look like "no-map/ShopifyOrder" (or with a backslash on Windows)
const rows = Object.entries(report)
    .filter(([key]) => key !== 'total')
    .map(([key, value]) => ({ name: key.split(/[\\/]/).pop(), lines: value.lines }))
    .filter((row) => ownNames.has(row.name))
    .sort((a, b) => a.lines.pct - b.lines.pct || a.name.localeCompare(b.name));

const covered = rows.reduce((sum, row) => sum + row.lines.covered, 0);
const total = rows.reduce((sum, row) => sum + row.lines.total, 0);
const overall = total ? ((covered / total) * 100).toFixed(1) : '0.0';

const lines = [
    '### Apex coverage',
    '',
    `Project classes and triggers: **${overall}%** (${covered}/${total} lines). Target per class: ${COVERAGE_TARGET}%.`,
    '',
    '| Class | Lines | Coverage |',
    '| --- | ---: | ---: |',
    ...rows.map(
        (row) =>
            `| ${row.name} | ${row.lines.covered}/${row.lines.total} | ${row.lines.pct}%${row.lines.pct < COVERAGE_TARGET ? ' ⚠️' : ''} |`
    )
];
console.log(lines.join('\n'));
