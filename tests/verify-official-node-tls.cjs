// Network integration test for the official Node.js build that GitHub Actions
// brings into job containers. It keeps the image's NODE_OPTIONS
// (--use-openssl-ca), and official builds use OPENSSLDIR=/etc/ssl, so the OS
// store must be reachable through /etc/ssl/cert.pem.
const https = require('node:https');

const urls = [
  'https://www.google.com/',
  // The artifact service used by actions/upload-artifact.
  'https://results-receiver.actions.githubusercontent.com/',
];

function get(url) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, response => {
      response.resume();
      console.log(`Official Node.js ${process.versions.node} connected to ${url}: HTTP ${response.statusCode}`);
      resolve();
    });
    request.setTimeout(30000, () => request.destroy(new Error(`Timeout: ${url}`)));
    request.on('error', reject);
  });
}

(async () => {
  for (const url of urls) await get(url);
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
