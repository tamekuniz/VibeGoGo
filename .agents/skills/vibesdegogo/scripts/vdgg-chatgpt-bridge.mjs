#!/usr/bin/env node
// Process-only workaround for a confirmed OS resolver failure on quick URLs.
import https from 'node:https';
import { Resolver } from 'node:dns/promises';
import { realpath } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

const checkout = await realpath(process.env.C2C_CHECKOUT || `${process.env.HOME}/codex-with-chatgpt`);
const workspace = await realpath(process.argv[2]);
const { startBridge } = await import(pathToFileURL(join(checkout, 'dist/bridge/server.js')));
const { CloudflaredQuickTunnel } = await import(pathToFileURL(join(checkout, 'dist/tunnel/cloudflared.js')));
const { Logger } = await import(pathToFileURL(join(checkout, 'dist/logger/index.js')));
const resolver = new Resolver();
resolver.setServers(['1.1.1.1']);
const fetchHealth = (url, init) => new Promise((resolve, reject) => {
  if (!/^https:\/\/[a-z0-9-]+\.trycloudflare\.com\/health$/.test(url)) {
    reject(new Error('Unexpected health URL'));
    return;
  }
  const request = https.get(url, {
    signal: init.signal,
    lookup: (host, options, callback) => resolver.resolve4(host).then(
      addresses => callback(null, options.all ? addresses.map(address => ({ address, family: 4 })) : addresses[0], 4),
      callback),
  }, response => {
    let body = '';
    response.on('data', chunk => { body += chunk; });
    response.on('error', reject);
    response.on('end', () => resolve(new Response(body, { status: response.statusCode })));
  });
  request.on('error', reject);
});
const logger = new Logger({ console: true, name: 'vdgg-chat-bridge' });
const bridge = await startBridge({ workspaceRoot: workspace, logger,
  tunnelProvider: new CloudflaredQuickTunnel(logger, undefined, { fetchImpl: fetchHealth }) });
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.once(signal, () => bridge.close().then(() => process.exit(0)));
}
