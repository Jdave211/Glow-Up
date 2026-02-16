const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');

// Credentials
const TEAM_ID = 'U8FPZXV6X6';
const KEY_ID = 'UP79TG8P94';
const CLIENT_ID = 'com.glowup.app'; // Bundle ID
const PRIVATE_KEY_PATH = path.join(__dirname, 'AuthKey_UP79TG8P94.p8');

try {
  const privateKey = fs.readFileSync(PRIVATE_KEY_PATH, 'utf8');

  // Generate the client secret
  const clientSecret = jwt.sign(
    {}, 
    privateKey, 
    {
      algorithm: 'ES256',
      keyid: KEY_ID,
      issuer: TEAM_ID,
      audience: 'https://appleid.apple.com',
      subject: CLIENT_ID,
      expiresIn: '180d' // Max 6 months
    }
  );

  console.log('\n✅ Apple Client Secret Generated (valid for 6 months):');
  console.log('---------------------------------------------------');
  console.log(clientSecret);
  console.log('---------------------------------------------------');
  console.log('\nCopy this value into your Supabase Dashboard > Auth > Providers > Apple > Secret Key');

} catch (error) {
  console.error('Error generating secret:', error.message);
  if (error.code === 'ENOENT') {
    console.error(`Could not find private key at: ${PRIVATE_KEY_PATH}`);
  }
}












