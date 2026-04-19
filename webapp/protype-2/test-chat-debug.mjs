import { chromium } from '@playwright/test';
import fs from 'fs';

const LOG = [];
const log = (...args) => {
  const msg = args.join(' ');
  console.log(msg);
  LOG.push(msg);
  // write immediately so we can tail the file
  fs.writeFileSync('debug-log.txt', LOG.join('\n') + '\n');
};

async function run() {
  log('🚀 Starting chat debug...');
  const browser = await chromium.launch({ headless: false, slowMo: 300 });
  const page = await browser.newPage();

  // ── Capture console messages ──
  page.on('console', msg => {
    log(`[console:${msg.type()}] ${msg.text()}`);
  });
  page.on('pageerror', err => {
    log(`[pageerror] ${err.message}`);
  });

  // ── Capture ALL network requests & responses ──
  const networkLog = [];
  page.on('request', req => {
    if (!req.url().match(/\.(png|jpg|svg|css|woff|ico)$/)) {
      networkLog.push({ direction: 'REQUEST', method: req.method(), url: req.url(), body: req.postDataJSON() ?? null });
    }
  });
  page.on('response', async resp => {
    const url = resp.url();
    if (url.includes('/ai_message') || url.includes('/message') || url.includes('/conversation')) {
      let body = null;
      try { body = await resp.json(); } catch { body = await resp.text().catch(() => null); }
      networkLog.push({ direction: 'RESPONSE', status: resp.status(), url, body });
      fs.writeFileSync('debug-network.json', JSON.stringify(networkLog, null, 2));
      log(`[network] ${resp.status()} ${url}`);
      log(`[response body] ${JSON.stringify(body)}`);
    }
  });
  page.on('requestfailed', req => {
    log(`[requestfailed] ${req.method()} ${req.url()} — ${req.failure()?.errorText}`);
  });

  // ── Navigate ──
  log('📍 Navigating to http://localhost:3002...');
  await page.goto('http://localhost:3002', { waitUntil: 'networkidle', timeout: 60000 });
  log('✅ Page loaded');

  // ── Wait for matrix ──
  await page.waitForSelector('[class*="tabulator"]', { timeout: 30000 });
  log('✅ Matrix visible');

  // ── Open chat sidebar ──
  const chatBtn = page.locator('button:has(svg.lucide-message-square)').first();
  await chatBtn.waitFor({ timeout: 15000 });
  await chatBtn.click();
  await page.waitForTimeout(1500);
  log('✅ Chat sidebar opened');

  // ── Take snapshot of sidebar ──
  await page.screenshot({ path: 'debug-1-sidebar.png' });

  // ── Type & send message ──
  const textarea = page.locator('textarea[placeholder="Type your message..."]');
  await textarea.waitFor({ timeout: 10000 });
  await textarea.fill('help me create a user journey on creating an ai agent driving journey map');
  log('✅ Message typed');
  await page.screenshot({ path: 'debug-2-before-send.png' });
  await textarea.press('Enter');
  log('✅ Message sent — waiting for response...');

  // ── Wait up to 60 s for the AI response ──
  log('⏳ Waiting for AI response (up to 60s)...');
  await page.waitForTimeout(60000);

  // ── Take final screenshot ──
  await page.screenshot({ path: 'debug-3-after-response.png' });
  log('✅ Final screenshot saved');

  // ── Dump all captured data ──
  fs.writeFileSync('debug-network.json', JSON.stringify(networkLog, null, 2));
  fs.writeFileSync('debug-log.txt', LOG.join('\n'));
  log('📄 Wrote debug-network.json and debug-log.txt');

  await browser.close();
  log('🏁 Done');
}

run().catch(err => {
  console.error('FATAL:', err);
  fs.writeFileSync('debug-log.txt', LOG.join('\n') + '\nFATAL: ' + err.message);
  process.exit(1);
});
