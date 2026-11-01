/**
 * Shared helpers for the project's Claude Code skill scripts.
 * Every Salesforce CLI call goes to TARGET_ORG; scripts cannot choose another org.
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const TARGET_ORG = 'orderhub';
const PROJECT_DIR = path.resolve(__dirname, '..', '..');

function quote(arg) {
    if (arg.includes('"')) {
        throw new Error(`Argument may not contain double quotes: ${arg}`);
    }
    return /[\s'&|<>^()%!]/.test(arg) ? `"${arg}"` : arg;
}

/**
 * Runs `sf <args> --target-org orderhub --json` and returns the parsed JSON.
 * The CLI exits non-zero on failures but still prints JSON, so stdout is always parsed.
 */
function sf(args) {
    const commandLine = ['sf', ...args, '--target-org', TARGET_ORG, '--json'].map(quote).join(' ');
    const result = spawnSync(commandLine, {
        cwd: PROJECT_DIR,
        shell: true,
        encoding: 'utf8',
        maxBuffer: 100 * 1024 * 1024,
        env: { ...process.env, SF_DISABLE_AUTOUPDATE: 'true', SF_AUTOUPDATE_DISABLE: 'true' }
    });
    const stdout = (result.stdout || '').trim();
    try {
        return JSON.parse(stdout.slice(stdout.indexOf('{')));
    } catch {
        throw new Error(`Could not parse CLI output of: ${commandLine}\n${stdout}\n${result.stderr || ''}`);
    }
}

function query(soql) {
    const response = sf(['data', 'query', '--query', soql]);
    if (response.status !== 0) {
        throw new Error(response.message || JSON.stringify(response));
    }
    return response.result.records;
}

/**
 * Runs anonymous Apex from a temporary file and throws if it fails to compile or run.
 */
function runApex(code) {
    const file = path.join(os.tmpdir(), `orderhub-${process.pid}-${Date.now()}.apex`);
    fs.writeFileSync(file, code);
    try {
        const response = sf(['apex', 'run', '--file', file]);
        const result = response.result || {};
        if (!result.compiled) {
            throw new Error(`Apex did not compile: ${result.compileProblem || response.message}`);
        }
        if (!result.success) {
            throw new Error(`Apex failed: ${result.exceptionMessage}`);
        }
        return result;
    } finally {
        fs.unlinkSync(file);
    }
}

function sleep(ms) {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

module.exports = { TARGET_ORG, PROJECT_DIR, sf, query, runApex, sleep };
