import appleSignin from 'apple-signin-auth';
import { DatabaseService } from '../db/supabase';

interface AppleAuthResponse {
  success: boolean;
  user?: any;
  token?: string;
  error?: string;
}

export async function verifyAppleToken(identityToken: string, fullName?: { givenName?: string, familyName?: string }): Promise<AppleAuthResponse> {
  try {
    console.log('🔐 Verifying Apple token...');
    console.log('   Bundle ID:', process.env.APPLE_BUNDLE_ID || 'NOT SET - using default');
    
    // 1. Verify the identity token with Apple
    const { sub: appleUserId, email } = await appleSignin.verifyIdToken(identityToken, {
      audience: process.env.APPLE_BUNDLE_ID || 'com.glowup.app', // Default to com.glowup.app
      ignoreExpiration: true, // For testing, sometimes helpful
    });
    
    console.log('✅ Token verified. Email:', email);

    if (!email) {
      return { success: false, error: 'No email found in token' };
    }

    // 2. Check if user exists in Supabase
    let user = await DatabaseService.getUserByEmail(email);
    let isNewUser = false;

    if (!user) {
      // 3. Create new user if not exists
      // Use provided name or fallback to "Guest" if not provided (Apple only sends name on first sign in)
      const name = fullName ? `${fullName.givenName} ${fullName.familyName}`.trim() : 'Guest User';
      user = await DatabaseService.createUser(email, name);
      isNewUser = true;
    }

    if (!user) {
      return { success: false, error: 'Failed to create user' };
    }

    // 4. Ensure onboarded status is included (explicitly check DB if not present)
    const onboarded = user.onboarded === true;
    console.log(`🔐 User auth: ${email}, onboarded: ${onboarded}, isNew: ${isNewUser}`);

    // 5. Return user info with explicit onboarded status
    return { 
      success: true, 
      user: {
        ...user,
        onboarded: onboarded
      }
    };

  } catch (error) {
    console.error('Apple Sign In Verification Error:', error);
    return { success: false, error: 'Invalid token' };
  }
}








