// Network integration test: only certificate errors count as a safe rejection.
// Connection timeouts, DNS failures, and general network errors fail the test.
const assert = require('node:assert/strict');
const https = require('node:https');
const puppeteer = require('/usr/local/lib/node_modules/puppeteer-core');

const hosts = [];
for (const intermediate of ['dv-g3b', 'dv-g3c', 'ov-g3b', 'ov-g3c', 'ev-g3b', 'ev-g3c']) {
  hosts.push(intermediate, intermediate + '-aaa');
}
hosts.push('dv-g3b-noct', 'dv-g3b-aaa-noct');
const urlFor = host => `https://${host}-emudhra.we-have-a-problem.com/`;

function nodeGet(url, shouldReject) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, response => {
      response.resume();
      if (shouldReject) reject(new Error(`Node.js accepted a distrusted chain: ${url}`));
      else resolve();
    });
    request.setTimeout(30000, () => request.destroy(new Error(`Timeout: ${url}`)));
    request.on('error', error => {
      const certificateErrors = new Set([
        'UNABLE_TO_GET_ISSUER_CERT_LOCALLY', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE',
        'CERT_UNTRUSTED', 'CERT_REVOKED', 'SELF_SIGNED_CERT_IN_CHAIN',
      ]);
      if (shouldReject && certificateErrors.has(error.code)) {
        console.log(`Node.js rejected ${url}: ${error.code}`);
        resolve();
      } else reject(error);
    });
  });
}

(async () => {
  await nodeGet('https://www.google.com/', false);
  for (const host of ['dv-g3b', 'dv-g3b-aaa', 'dv-g3b-noct', 'dv-g3b-aaa-noct']) {
    await nodeGet(urlFor(host), true);
  }
  const browser = await puppeteer.launch({
    executablePath: process.env.CHROME_PATH || '/usr/local/bin/chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  try {
    const page = await browser.newPage();
    await page.goto('https://www.google.com/', {waitUntil: 'domcontentloaded', timeout: 30000});
    for (const host of hosts) {
      const url = urlFor(host);
      let rejected = false;
      try {
        await page.goto(url, {waitUntil: 'domcontentloaded', timeout: 30000});
      } catch (error) {
        // Require an untrusted-authority/revoked error, not merely expired certs
        // or missing CT, which would mask a missing distrust policy.
        if (!/net::ERR_CERT_(AUTHORITY_INVALID|REVOKED)\b/.test(error.message)) throw error;
        console.log(`Chrome rejected ${url}: ${error.message.split(' at ')[0]}`);
        rejected = true;
      }
      assert(rejected, `Chrome accepted a distrusted chain: ${url}`);
    }
    console.log(`Chrome ${await browser.version()}: all ${hosts.length} chains rejected`);
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
