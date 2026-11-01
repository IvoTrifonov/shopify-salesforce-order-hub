#!/usr/bin/env node
// Reports what changed since the .claude configuration was last updated, and where it drifted. See SKILL.md.
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const PROJECT_DIR = path.resolve(__dirname, '..', '..', '..');
const SOURCE_DIR = path.join(PROJECT_DIR, 'force-app', 'main', 'default');
const CLAUDE_DIR = path.join(PROJECT_DIR, '.claude');

// Only trailing whitespace is trimmed: `git status --porcelain` lines start with a significant space
const git = (args) => execSync(`git ${args}`, { cwd: PROJECT_DIR, encoding: 'utf8', maxBuffer: 50 * 1024 * 1024 }).trimEnd();

// Kinds of files, in report order. First match wins.
const KINDS = [
    ['Apex tests', /\/classes\/\w+Test\.cls$/],
    ['Apex classes', /\/classes\/\w+\.cls$/],
    ['Triggers', /\/triggers\/\w+\.trigger$/],
    ['Platform Events', /\/objects\/\w+__e\//],
    ['Objects and fields', /\/objects\//],
    ['LWC', /\/lwc\//],
    ['Aura', /\/aura\//],
    ['Flows', /\/flows\//],
    ['Permission sets', /\/permissionsets\//],
    ['Static resources', /\/staticresources\//],
    ['Other metadata', /^force-app\//],
    ['Claude configuration', /^\.claude\//],
    ['CI/CD', /^\.github\//],
    ['Docs and README', /^(docs\/|README\.md$)/],
    ['Project config', /^(sfdx-project\.json|package\.json|config\/|scripts\/|\.gitignore$|\.forceignore$)/],
    ['Other', /./]
];

function kindOf(file) {
    return KINDS.find(([, pattern]) => pattern.test(file))[0];
}

function changedFiles(base) {
    const files = new Map();
    const add = (status, file) => {
        if (!file.endsWith('-meta.xml') || file.includes('/objects/') || file.includes('/permissionsets/')) {
            files.set(file, status);
        }
    };
    const committed = base ? git(`diff --name-status ${base} HEAD`) : '';
    const uncommitted = git('status --porcelain');
    committed
        .split('\n')
        .filter(Boolean)
        .forEach((line) => {
            const [status, ...paths] = line.split('\t');
            add(status[0], paths[paths.length - 1]);
        });
    uncommitted
        .split('\n')
        .filter(Boolean)
        .forEach((line) => {
            const status = line.slice(0, 2).trim();
            const file = line.slice(3).split(' -> ').pop().replace(/"/g, '');
            if (file.endsWith('/')) {
                // An untracked folder: list the files inside it
                git(`ls-files --others --exclude-standard -- "${file}"`)
                    .split('\n')
                    .filter(Boolean)
                    .forEach((f) => add('A', f));
            } else {
                add(status === '??' ? 'A' : status[0], file);
            }
        });
    return files;
}

function listNames(folder, pattern) {
    const dir = path.join(SOURCE_DIR, folder);
    if (!fs.existsSync(dir)) {
        return [];
    }
    return fs
        .readdirSync(dir)
        .map((entry) => entry.match(pattern))
        .filter(Boolean)
        .map((match) => match[1]);
}

function projectComponents() {
    return {
        classes: listNames('classes', /^(\w+)\.cls$/).filter((name) => !name.endsWith('Test')),
        triggers: listNames('triggers', /^(\w+)\.trigger$/),
        objects: listNames('objects', /^(\w+__(?:c|e|mdt))$/),
        permissionSets: listNames('permissionsets', /^(\w+)\.permissionset-meta\.xml$/),
        lwc: listNames('lwc', /^([a-z]\w*)$/),
        staticResources: listNames('staticresources', /^(\w+)\.resource-meta\.xml$/)
    };
}

function claudeText() {
    const texts = [];
    const walk = (dir) => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                walk(full);
            } else if (entry.name.endsWith('.md') && entry.name !== 'learned-topics.md') {
                texts.push(fs.readFileSync(full, 'utf8'));
            }
        }
    };
    walk(CLAUDE_DIR);
    return texts.join('\n');
}

function main() {
    const base = git('log -1 --format=%h -- .claude') || null;
    console.log(base ? `Changes since ${base} (last commit touching .claude/):` : 'No commit touches .claude/ yet; reviewing uncommitted work.');

    const commits = base ? git(`log --oneline ${base}..HEAD`) : '';
    console.log(`\nCommits since then: ${commits ? commits.split('\n').length : 0}`);
    if (commits) {
        commits.split('\n').forEach((line) => console.log(`  ${line}`));
    }

    const files = changedFiles(base);
    const groups = new Map();
    for (const [file, status] of files) {
        const kind = kindOf(file);
        if (!groups.has(kind)) {
            groups.set(kind, []);
        }
        groups.get(kind).push(`${status} ${file}`);
    }
    console.log(`\nChanged files (committed + uncommitted): ${files.size}`);
    for (const [kind] of KINDS) {
        if (groups.has(kind)) {
            console.log(`  ${kind}:`);
            groups.get(kind).sort().forEach((line) => console.log(`    ${line}`));
        }
    }

    const added = [...files].filter(([, status]) => status === 'A').map(([file]) => file);
    const newComponents = added.filter((file) =>
        /\/(classes\/(?!\w+Test\.cls)\w+\.cls|triggers\/\w+\.trigger|objects\/\w+__[ce]\/\w+__[ce]\.object-meta\.xml|lwc\/\w+\/\w+\.js|flows\/.+|aura\/\w+\/\w+\.cmp)$|^\.github\/workflows\//.test(file)
    );
    console.log('\nNew components:');
    console.log(newComponents.length ? newComponents.map((f) => `  ${f}`).join('\n') : '  none');

    const text = claudeText();
    const components = projectComponents();
    const allNames = new Set(Object.values(components).flat());
    console.log('\nDrift: project components not mentioned in .claude/:');
    let drift = 0;
    for (const [group, names] of Object.entries(components)) {
        const missing = names.filter((name) => !new RegExp(`\\b${name}\\b`).test(text));
        if (missing.length) {
            drift += missing.length;
            console.log(`  ${group}: ${missing.join(', ')}`);
        }
    }
    if (!drift) {
        console.log('  none');
    }

    // A name is stale when it was a component in the repo's history but no longer exists.
    // Checking history avoids flagging platform names (OrderItem) and examples in the docs.
    const historical = new Set(
        git('log --all --format= --name-only --diff-filter=A -- force-app')
            .split('\n')
            .map((file) => file.match(/\/(?:classes|triggers|staticresources|permissionsets)\/(\w+)\.|\/objects\/(\w+__[cem]\w*)\//))
            .filter(Boolean)
            .map((match) => match[1] || match[2])
    );
    const mentioned = new Set([...text.matchAll(/`(\w+)`/g)].map((m) => m[1]));
    const stale = [...mentioned].filter((name) => historical.has(name) && !allNames.has(name));
    console.log('\nDrift: names in .claude/ not found in force-app (check whether they are stale):');
    console.log(stale.length ? `  ${stale.join(', ')}` : '  none');
}

try {
    main();
} catch (error) {
    console.error(error.message);
    process.exit(1);
}
