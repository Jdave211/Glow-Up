"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.verifyAppleToken = verifyAppleToken;
const apple_signin_auth_1 = __importDefault(require("apple-signin-auth"));
const supabase_1 = require("../db/supabase");
async function verifyAppleToken(identityToken, fullName) {
    try {
        console.log('🔐 Verifying Apple token...');
        console.log('   Bundle ID:', process.env.APPLE_BUNDLE_ID || 'NOT SET - using default');
        // 1. Verify the identity token with Apple
        const { sub: appleUserId, email } = await apple_signin_auth_1.default.verifyIdToken(identityToken, {
            audience: process.env.APPLE_BUNDLE_ID || 'com.glowup.app', // Default to com.glowup.app
            ignoreExpiration: true, // For testing, sometimes helpful
        });
        console.log('✅ Token verified. Email:', email);
        if (!email) {
            return { success: false, error: 'No email found in token' };
        }
        // 2. Check if user exists in Supabase
        let user = await supabase_1.DatabaseService.getUserByEmail(email);
        let isNewUser = false;
        if (!user) {
            // 3. Create new user if not exists
            // Use provided name or fallback to "Guest" if not provided (Apple only sends name on first sign in)
            const name = fullName ? `${fullName.givenName} ${fullName.familyName}`.trim() : 'Guest User';
            user = await supabase_1.DatabaseService.createUser(email, name);
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
    }
    catch (error) {
        console.error('Apple Sign In Verification Error:', error);
        return { success: false, error: 'Invalid token' };
    }
}
