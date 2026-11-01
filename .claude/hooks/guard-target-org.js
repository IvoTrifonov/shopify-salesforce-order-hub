#!/usr/bin/env node
/**
 * Claude Code PreToolUse hook: keeps Salesforce CLI commands on this project's org.
 *
 * Blocks (exit code 2) any `sf` / `sfdx` command that names an org other than
 * the allowed ones, and any org-affecting command that does not name an org at
 * all, so a command can never fall back to whatever the default org is.
 */
const ALLOWED_ORGS = ['orderhub'];

// Subcommands that only read local state or list orgs and are safe without a target org
const SAFE_WITHOUT_TARGET = [
    /^(--version|-v|version|help|--help|-h)\b/,
    /^org list\b/,
    /^config (get|list)\b/,
    /^alias list\b/,
    /^plugins\b/,
    /^update\b/,
    /^project generate\b/,
    /^(apex|lightning|static-resource|visualforce) generate\b/,
    /^template generate\b/
];

function readStdin() {
    return new Promise((resolve) => {
        let data = '';
        process.stdin.on('data', (chunk) => (data += chunk));
        process.stdin.on('end', () => resolve(data));
    });
}

function block(message) {
    process.stderr.write(`Blocked by .claude/hooks/guard-target-org.js: ${message}\n`);
    process.exit(2);
}

// Splits a shell command line into individual commands, e.g. `a && b | c; d`
function splitCommands(commandLine) {
    return commandLine.split(/&&|\|\||;|\||\r?\n/).map((part) => part.trim()).filter(Boolean);
}

function checkSfCommand(command) {
    const match = command.match(/(?:^|[\s"'/\\])(sf|sfdx)(?:\.cmd|\.exe)?\s+(.*)$/);
    if (!match) {
        return;
    }
    const args = match[2].trim();

    if (/^config set\b/.test(args) && /target-org/.test(args)) {
        block('changing the default target org is not allowed for this project.');
    }

    const orgs = [...args.matchAll(/(?:--target-org|--target-dev-hub|-o)(?:=|\s+)["']?([^\s"']+)/g)].map((m) => m[1]);
    const disallowed = orgs.filter((org) => !ALLOWED_ORGS.includes(org));
    if (disallowed.length > 0) {
        block(`org "${disallowed.join('", "')}" is not allowed. Use --target-org ${ALLOWED_ORGS[0]}.`);
    }
    if (orgs.length === 0 && !SAFE_WITHOUT_TARGET.some((pattern) => pattern.test(args))) {
        block(`pass --target-org ${ALLOWED_ORGS[0]} explicitly instead of relying on the default org.`);
    }
}

async function main() {
    let input;
    try {
        input = JSON.parse(await readStdin());
    } catch {
        return; // Not a hook payload this script understands; do not block
    }
    const commandLine = input?.tool_input?.command;
    if (typeof commandLine !== 'string') {
        return;
    }
    splitCommands(commandLine).forEach(checkSfCommand);
}

main();
