import { readFile, writeFile } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { chromium } from 'playwright';
const configuration = JSON.parse(await readFile(process.argv[2], 'utf8'));
const state = randomUUID();
const verifier = 'v'.repeat(64);
const query = new URLSearchParams({ client_id: configuration.clientId, redirect_uri: configuration.callback,
  response_type: 'code', scope: 'openid', state, code_challenge_method: 'S256',
  code_challenge: createHash('sha256').update(verifier).digest('base64url') });
const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  let accept;
  let reject;
  const result = new Promise((resolve, fail) => { accept = resolve; reject = fail; });
  const timer = setTimeout(() => reject(new Error('OAuth browser callback timeout')), 30000);
  try {
    page.on('request', request => {
      const url = new URL(request.url());
      if (url.origin + url.pathname !== configuration.callback) return;
      if (url.searchParams.get('state') !== state || !url.searchParams.get('code')) reject(new Error('Invalid authorization response'));
      else accept(url.searchParams.get('code'));
    });
    await page.goto(`${configuration.issuer}/protocol/openid-connect/auth?${query}`);
    await page.locator('#username').fill('synthetic-user');
    await page.locator('#password').fill('synthetic-password');
    await page.locator('#kc-login').click({ noWaitAfter: true });
    await writeFile(process.argv[3], JSON.stringify({ code: await result, verifier }));
  } finally { clearTimeout(timer); }
} finally { await browser.close(); }
