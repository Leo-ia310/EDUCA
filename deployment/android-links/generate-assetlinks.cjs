// Public certificate fingerprints only. Never pass a keystore or its password.
const fs = require('node:fs');
const path = require('node:path');

const fingerprints = process.argv.slice(2).map(value => value.toUpperCase());
if (!fingerprints.length || fingerprints.some(value => !/^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$/.test(value))) {
  console.error('Usage: node deployment/android-links/generate-assetlinks.cjs SHA256_FINGERPRINT [SECOND_FINGERPRINT]');
  process.exit(1);
}
const gradle = fs.readFileSync(path.resolve(__dirname, '../../frontend/android/app/build.gradle.kts'), 'utf8');
const packageName = gradle.match(/applicationId\s*=\s*"([^"]+)"/)?.[1];
if (!packageName) throw new Error('Android applicationId was not found.');
const output = path.join(__dirname, 'public/.well-known/assetlinks.json');
fs.mkdirSync(path.dirname(output), {recursive: true});
fs.writeFileSync(output, JSON.stringify([{
  relation: ['delegate_permission/common.handle_all_urls'],
  target: {
    namespace: 'android_app',
    package_name: packageName,
    sha256_cert_fingerprints: [...new Set(fingerprints)],
  },
}], null, 2) + '\n');
console.log(`Generated ${output} for ${packageName}. Publish at https://nivramop.com/.well-known/assetlinks.json`);
