#!/usr/bin/env node
// Lists, inspects and replays Shopify sync logs in the orderhub org. See SKILL.md.
const { query, runApex, sleep } = require('../../lib/sf');

const STATUSES = ['Pending', 'Success', 'Error', 'Retrying', 'Skipped'];
const REPLAY_TIMEOUT_MS = 30000;

function logName(value) {
    if (!/^LOG-\d+$/.test(value || '')) {
        throw new Error('Expected a log name such as LOG-000004.');
    }
    return value;
}

function firstLine(text, max = 90) {
    const line = (text || '').split('\n')[0];
    return line.length > max ? line.slice(0, max - 1) + '…' : line;
}

function table(rows, columns) {
    const widths = columns.map((c) => Math.max(c.length, ...rows.map((r) => String(r[c] ?? '').length)));
    const format = (values) => values.map((v, i) => String(v ?? '').padEnd(widths[i])).join('  ');
    console.log(format(columns));
    console.log(widths.map((w) => '-'.repeat(w)).join('  '));
    rows.forEach((r) => console.log(format(columns.map((c) => r[c]))));
}

function invoicesByOrder(orderIds) {
    const byOrder = new Map();
    if (!orderIds.length) {
        return byOrder;
    }
    const ids = orderIds.map((id) => `'${id}'`).join(',');
    for (const inv of query(
        `SELECT Name, Order__c, Status__c, Total_Amount__c FROM Invoice__c WHERE Order__c IN (${ids}) ORDER BY Name`
    )) {
        if (!byOrder.has(inv.Order__c)) {
            byOrder.set(inv.Order__c, []);
        }
        byOrder.get(inv.Order__c).push(inv);
    }
    return byOrder;
}

function list(args) {
    let limit = 10;
    let status = null;
    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--limit') {
            limit = parseInt(args[++i], 10);
        } else if (args[i] === '--status') {
            status = args[++i];
        }
    }
    if (!Number.isInteger(limit) || limit < 1 || limit > 200) {
        throw new Error('--limit must be between 1 and 200.');
    }
    if (status && !STATUSES.includes(status)) {
        throw new Error(`--status must be one of ${STATUSES.join(', ')}.`);
    }

    const where = status ? `WHERE Status__c = '${status}'` : '';
    const logs = query(
        `SELECT Name, CreatedDate, Direction__c, Event_Topic__c, Status__c, HTTP_Status_Code__c, Shopify_Reference__c, ` +
            `Order__c, Order__r.Name, Error_Message__c FROM Sync_Log__c ${where} ORDER BY CreatedDate DESC LIMIT ${limit}`
    );
    if (!logs.length) {
        console.log('No sync logs found.');
        return;
    }
    const invoices = invoicesByOrder([...new Set(logs.map((l) => l.Order__c).filter(Boolean))]);
    table(
        logs.map((l) => ({
            Log: l.Name,
            Created: (l.CreatedDate || '').replace('T', ' ').slice(0, 19),
            Dir: l.Direction__c,
            Topic: l.Event_Topic__c,
            Status: l.Status__c,
            HTTP: l.HTTP_Status_Code__c,
            'Shopify ID': l.Shopify_Reference__c,
            Order: l.Order__r ? l.Order__r.Name : '',
            Invoices: (invoices.get(l.Order__c) || []).map((i) => `${i.Name} (${i.Status__c})`).join(', '),
            Error: firstLine(l.Error_Message__c, 60)
        })),
        ['Log', 'Created', 'Dir', 'Topic', 'Status', 'HTTP', 'Shopify ID', 'Order', 'Invoices', 'Error']
    );
}

function show(args) {
    const name = logName(args[0]);
    const [log] = query(
        `SELECT Id, Name, CreatedDate, LastModifiedDate, Direction__c, Event_Topic__c, Status__c, HTTP_Status_Code__c, ` +
            `Shopify_Reference__c, Retry_Count__c, Order__c, Payload__c, Error_Message__c FROM Sync_Log__c WHERE Name = '${name}'`
    );
    if (!log) {
        throw new Error(`${name} not found.`);
    }
    console.log(
        `${log.Name}  ${log.Direction__c} ${log.Event_Topic__c || ''}  ->  ${log.Status__c} (HTTP ${log.HTTP_Status_Code__c ?? '-'})`
    );
    console.log(
        `Created ${log.CreatedDate}, last modified ${log.LastModifiedDate}, retries ${log.Retry_Count__c ?? 0}`
    );
    console.log(`Shopify reference: ${log.Shopify_Reference__c || '-'}`);

    if (log.Payload__c) {
        console.log(`\nPayload: ${log.Payload__c.length} characters`);
        try {
            const p = JSON.parse(log.Payload__c);
            const fields = [
                'id',
                'name',
                'financial_status',
                'fulfillment_status',
                'total_price',
                'currency',
                'updated_at',
                'test'
            ];
            fields.filter((f) => f in p).forEach((f) => console.log(`  ${f}: ${JSON.stringify(p[f])}`));
            if (Array.isArray(p.line_items)) {
                console.log(`  line_items: ${p.line_items.length}, shipping_lines: ${(p.shipping_lines || []).length}`);
            }
        } catch {
            console.log('  (not valid JSON)');
        }
    } else {
        console.log('\nPayload: not stored');
    }

    if (log.Error_Message__c) {
        console.log(`\nError:\n${log.Error_Message__c}`);
    }

    if (log.Order__c) {
        const [order] = query(
            `SELECT Name, Status, EffectiveDate, TotalAmount, Shopify_Total_Price__c, Financial_Status__c, ` +
                `Shopify_Fulfillment_Status__c, Account.Name, BillToContact.Email FROM Order WHERE Id = '${log.Order__c}'`
        );
        console.log(
            `\nOrder ${order.Name}: ${order.Status}, ${order.EffectiveDate}, financial ${order.Financial_Status__c}, ` +
                `fulfillment ${order.Shopify_Fulfillment_Status__c}`
        );
        console.log(
            `  Customer: ${order.Account ? order.Account.Name : '-'} <${order.BillToContact ? order.BillToContact.Email : '-'}>`
        );
        const mismatch =
            Number(order.TotalAmount) !== Number(order.Shopify_Total_Price__c) ? '  <-- totals differ' : '';
        console.log(`  TotalAmount ${order.TotalAmount} / Shopify total ${order.Shopify_Total_Price__c}${mismatch}`);
        const items = query(
            `SELECT Product2.Name, Variant_Title__c, Description, Quantity, UnitPrice, TotalPrice FROM OrderItem ` +
                `WHERE OrderId = '${log.Order__c}' ORDER BY Shopify_Line_Item_Id__c`
        );
        items.forEach((i) =>
            console.log(
                `  - ${i.Quantity} x ${i.Product2 ? i.Product2.Name : '?'}${i.Variant_Title__c ? ' (' + i.Variant_Title__c + ')' : ''} @ ${i.UnitPrice} = ${i.TotalPrice}`
            )
        );
        const invoices = invoicesByOrder([log.Order__c]).get(log.Order__c) || [];
        console.log(
            `  Invoices: ${invoices.length ? invoices.map((i) => `${i.Name} ${i.Status__c} ${i.Total_Amount__c}`).join(', ') : 'none'}`
        );
    }
}

function replay(args) {
    const name = logName(args[0]);
    runApex(`
Sync_Log__c log = [SELECT Id, Direction__c, Event_Topic__c, Payload__c FROM Sync_Log__c WHERE Name = '${name}'];
if (log.Direction__c != 'Inbound' || String.isBlank(log.Payload__c)) {
    throw new IllegalArgumentException('Only inbound logs with a stored payload can be replayed.');
}
if (!ShopifyWebhookProcessor.HANDLED_TOPICS.contains(log.Event_Topic__c)) {
    throw new IllegalArgumentException('No handler for topic ' + log.Event_Topic__c + '.');
}
log.Status__c = 'Pending';
log.Error_Message__c = null;
update log;
EventBus.publish(new Shopify_Webhook__e(Sync_Log_Id__c = log.Id, Topic__c = log.Event_Topic__c));
`);
    console.log(`${name} set to Pending and Shopify_Webhook__e published. Waiting for the processor...`);

    const deadline = Date.now() + REPLAY_TIMEOUT_MS;
    let log;
    do {
        sleep(2000);
        [log] = query(`SELECT Status__c, Order__r.Name, Error_Message__c FROM Sync_Log__c WHERE Name = '${name}'`);
    } while (log.Status__c === 'Pending' && Date.now() < deadline);

    if (log.Status__c === 'Pending') {
        console.log(
            `Still Pending after ${REPLAY_TIMEOUT_MS / 1000}s. Check Setup > Platform Events > Shopify Webhook > Subscriptions.`
        );
        process.exit(1);
    }
    console.log(`Result: ${log.Status__c}${log.Order__r ? ', Order ' + log.Order__r.Name : ''}`);
    if (log.Error_Message__c) {
        console.log(firstLine(log.Error_Message__c, 300));
    }
    process.exit(log.Status__c === 'Success' ? 0 : 1);
}

const [command, ...rest] = process.argv.slice(2);
const commands = { list, show, replay };
try {
    if (!commands[command]) {
        throw new Error('Usage: sync-status.js list [--limit N] [--status S] | show LOG-x | replay LOG-x');
    }
    commands[command](rest);
} catch (error) {
    console.error(error.message);
    process.exit(1);
}
