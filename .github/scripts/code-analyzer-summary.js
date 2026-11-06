/**
 * Turns Code Analyzer's JSON results into Markdown for the GitHub job summary: the number of
 * violations per severity and a table of the ones that fail the build.
 *
 * Usage: node code-analyzer-summary.js <code-analyzer-results.json>
 */
const fs = require('fs');
const path = require('path');

// Must match --severity-threshold in ci.yml
const FAILING_SEVERITY = 2;
const SEVERITY_NAMES = { 1: 'Critical', 2: 'High', 3: 'Moderate', 4: 'Low', 5: 'Info' };
const MAX_ROWS = 50;

const reportPath = process.argv[2];
if (!reportPath || !fs.existsSync(reportPath)) {
    console.log('### Static analysis\n\nNo Code Analyzer results were produced (see the step log).');
    process.exit(0);
}

const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
const violations = report.violations ?? [];

function location(violation) {
    const loc = violation.locations?.[violation.primaryLocationIndex ?? 0] ?? {};
    const file = loc.file ? path.relative(process.cwd(), loc.file).replace(/\\/g, '/') : '?';
    return loc.startLine ? `${file}:${loc.startLine}` : file;
}

const counts = Object.keys(SEVERITY_NAMES).map(
    (severity) => `${SEVERITY_NAMES[severity]}: ${violations.filter((v) => v.severity === Number(severity)).length}`
);
const failing = violations
    .filter((v) => v.severity <= FAILING_SEVERITY)
    .sort((a, b) => a.severity - b.severity || location(a).localeCompare(location(b)));

const lines = [
    '### Static analysis',
    '',
    `Code Analyzer found **${violations.length}** violations (${counts.join(', ')}).`,
    `Severity ${FAILING_SEVERITY} or higher fails the build; the full report is in the \`code-analyzer-results\` artifact.`
];
if (failing.length > 0) {
    lines.push(
        '',
        '| Severity | Rule | Location | Message |',
        '| --- | --- | --- | --- |',
        ...failing
            .slice(0, MAX_ROWS)
            .map(
                (v) =>
                    `| ${SEVERITY_NAMES[v.severity]} | ${v.engine}:${v.rule} | ${location(v)} | ${String(v.message).replace(/\|/g, '\\|').trim()} |`
            )
    );
    if (failing.length > MAX_ROWS) {
        lines.push('', `…and ${failing.length - MAX_ROWS} more.`);
    }
}
console.log(lines.join('\n'));
