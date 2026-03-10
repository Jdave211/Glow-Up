"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.DatabaseService = exports.supabase = void 0;
const supabase_js_1 = require("@supabase/supabase-js");
const crypto_1 = __importDefault(require("crypto"));
// Supabase Configuration
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!supabaseUrl) {
    throw new Error('SUPABASE_URL is not set. Make sure it is configured in your environment (e.g. Heroku Config Vars).');
}
if (!supabaseAnonKey) {
    console.warn('⚠️ SUPABASE_ANON_KEY is not set. Public anon operations may fail.');
}
if (!supabaseServiceRoleKey) {
    console.warn('⚠️ SUPABASE_SERVICE_ROLE_KEY is not set. Server-side privileged operations will not be available.');
}
// Prefer service role for server-side operations, fall back to anon only if absolutely necessary
const supabaseKey = supabaseServiceRoleKey || supabaseAnonKey;
exports.supabase = (0, supabase_js_1.createClient)(supabaseUrl, supabaseKey);
// Database service functions
class DatabaseService {
    static isIgnorableMissingTableError(error) {
        if (!error || typeof error !== 'object')
            return false;
        const code = error.code;
        return code === '42P01';
    }
    static isMissingColumnError(error) {
        if (!error || typeof error !== 'object')
            return false;
        const code = error.code;
        const message = String(error.message ?? '').toLowerCase();
        return code === '42703' || code === 'PGRST204' || (message.includes('column') && message.includes('does not exist'));
    }
    static isStoragePathRef(ref) {
        if (typeof ref !== 'string' || !ref)
            return false;
        return !ref.startsWith('http://') && !ref.startsWith('https://') && !ref.startsWith('data:');
    }
    static normalizeRoutineKey(input) {
        if (!input)
            return null;
        const normalized = String(input)
            .toUpperCase()
            .replace(/[^A-Z0-9]/g, '');
        return normalized.length >= 6 ? normalized : null;
    }
    static extractRoutineKey(routineData) {
        const key = routineData?.meta?.routine_key ||
            routineData?.routine_key ||
            null;
        return this.normalizeRoutineKey(key);
    }
    static generateRoutineKeyCandidate(length = 8) {
        const bytes = crypto_1.default.randomBytes(length);
        const chars = this.ROUTINE_KEY_ALPHABET;
        let out = '';
        for (let i = 0; i < bytes.length; i++) {
            out += chars[bytes[i] % chars.length];
        }
        return out;
    }
    static async generateUniqueRoutineKey(maxAttempts = 8) {
        for (let i = 0; i < maxAttempts; i++) {
            const candidate = this.generateRoutineKeyCandidate(8);
            const existing = await this.getRoutineByShareKey(candidate);
            if (!existing)
                return candidate;
        }
        const fallback = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`
            .toUpperCase()
            .replace(/[^A-Z0-9]/g, '');
        return fallback.slice(0, 12);
    }
    static attachRoutineKey(routineData, routineKey) {
        const base = (routineData && typeof routineData === 'object') ? { ...routineData } : {};
        const meta = (base.meta && typeof base.meta === 'object') ? { ...base.meta } : {};
        meta.routine_key = routineKey;
        return {
            ...base,
            routine_key: routineKey,
            meta,
        };
    }
    // ═══════════════════════════════════════════════════════════════
    // USER OPERATIONS
    // ═══════════════════════════════════════════════════════════════
    static async createUser(email, name) {
        const { data, error } = await exports.supabase
            .from('users')
            .insert({ email, name })
            .select()
            .single();
        if (error) {
            console.error('Error creating user:', error);
            return null;
        }
        return data;
    }
    static async getUserByEmail(email) {
        const { data, error } = await exports.supabase
            .from('users')
            .select('*')
            .eq('email', email)
            .single();
        if (error)
            return null;
        return data;
    }
    static async getOrCreateUser(email, name) {
        let user = await this.getUserByEmail(email);
        if (!user) {
            user = await this.createUser(email, name);
        }
        return user;
    }
    static async getUserById(userId) {
        const { data, error } = await exports.supabase
            .from('users')
            .select('*')
            .eq('id', userId)
            .single();
        if (error)
            return null;
        return data;
    }
    static async getUserPhotoStoragePaths(userId) {
        const paths = new Set();
        const addPath = (value) => {
            if (this.isStoragePathRef(value)) {
                paths.add(value);
            }
        };
        const { data: profileRows, error: profileError } = await exports.supabase
            .from('skin_profiles')
            .select('photo_front_url, photo_left_url, photo_right_url, photo_scalp_url')
            .eq('user_id', userId);
        if (profileError && !this.isIgnorableMissingTableError(profileError)) {
            console.error('Error fetching skin profile photo refs:', profileError);
        }
        for (const row of profileRows || []) {
            addPath(row.photo_front_url);
            addPath(row.photo_left_url);
            addPath(row.photo_right_url);
            addPath(row.photo_scalp_url);
        }
        const { data: checkInRows, error: checkInError } = await exports.supabase
            .from('photo_check_ins')
            .select('photo_front_url, photo_left_url, photo_right_url')
            .eq('user_id', userId);
        if (checkInError && !this.isIgnorableMissingTableError(checkInError)) {
            console.error('Error fetching check-in photo refs:', checkInError);
        }
        for (const row of checkInRows || []) {
            addPath(row.photo_front_url);
            addPath(row.photo_left_url);
            addPath(row.photo_right_url);
        }
        return Array.from(paths);
    }
    static async deleteUserAccount(userId) {
        const tableDeletes = [
            { table: 'routine_checkins', column: 'user_id' },
            { table: 'routine_streaks', column: 'user_id' },
            { table: 'skin_insights', column: 'user_id' },
            { table: 'cart_items', column: 'user_id' },
            { table: 'photo_check_ins', column: 'user_id' },
            { table: 'routines', column: 'user_id' },
            { table: 'skin_profiles', column: 'user_id' },
            { table: 'profiles', column: 'user_id' },
        ];
        const { data: conversations, error: conversationsError } = await exports.supabase
            .from('chat_conversations')
            .select('id')
            .eq('user_id', userId);
        if (conversationsError && !this.isIgnorableMissingTableError(conversationsError)) {
            console.error('Error loading conversations for account deletion:', conversationsError);
            return false;
        }
        const conversationIds = (conversations || []).map((row) => row.id);
        if (conversationIds.length > 0) {
            const { error: messagesDeleteError } = await exports.supabase
                .from('chat_messages')
                .delete()
                .in('conversation_id', conversationIds);
            if (messagesDeleteError && !this.isIgnorableMissingTableError(messagesDeleteError)) {
                console.error('Error deleting chat messages during account deletion:', messagesDeleteError);
                return false;
            }
        }
        const { error: conversationsDeleteError } = await exports.supabase
            .from('chat_conversations')
            .delete()
            .eq('user_id', userId);
        if (conversationsDeleteError && !this.isIgnorableMissingTableError(conversationsDeleteError)) {
            console.error('Error deleting conversations during account deletion:', conversationsDeleteError);
            return false;
        }
        for (const target of tableDeletes) {
            const { error } = await exports.supabase
                .from(target.table)
                .delete()
                .eq(target.column, userId);
            if (error && !this.isIgnorableMissingTableError(error)) {
                console.error(`Error deleting ${target.table} during account deletion:`, error);
                return false;
            }
        }
        const { error: userDeleteError } = await exports.supabase
            .from('users')
            .delete()
            .eq('id', userId);
        if (userDeleteError && !this.isIgnorableMissingTableError(userDeleteError)) {
            console.error('Error deleting user during account deletion:', userDeleteError);
            return false;
        }
        return true;
    }
    static async markUserOnboarded(userId) {
        console.log('🔄 Attempting to mark user onboarded:', userId);
        const { data, error } = await exports.supabase
            .from('users')
            .update({ onboarded: true })
            .eq('id', userId)
            .select()
            .single();
        if (error) {
            console.error('❌ Error marking user onboarded:', error);
            console.error('Error details:', JSON.stringify(error, null, 2));
            return false;
        }
        console.log('✅ User onboarded update result:', data);
        return true;
    }
    static async isUserOnboarded(userId) {
        const { data, error } = await exports.supabase
            .from('users')
            .select('onboarded')
            .eq('id', userId)
            .single();
        if (error)
            return false;
        return data?.onboarded === true;
    }
    static async getUserSubscriptionStatus(userId) {
        const { data, error } = await exports.supabase
            .from('users')
            .select([
            'subscription_status',
            'subscription_plan',
            'subscription_product_id',
            'subscription_expires_at',
            'subscription_last_verified_at',
            'subscription_transaction_id',
            'subscription_original_transaction_id',
            'subscription_environment',
        ].join(', '))
            .eq('id', userId)
            .single();
        if (error) {
            if (this.isMissingColumnError(error)) {
                return {
                    isPremium: false,
                    status: 'inactive',
                    plan: null,
                    productId: null,
                    expiresAt: null,
                    lastVerifiedAt: null,
                    transactionId: null,
                    originalTransactionId: null,
                    environment: null,
                };
            }
            console.error('Error loading user subscription status:', error);
            return null;
        }
        const row = (data ?? {});
        const status = String(row.subscription_status ?? 'inactive').toLowerCase();
        const expiresAtRaw = typeof row.subscription_expires_at === 'string' ? row.subscription_expires_at : null;
        const expiresAt = expiresAtRaw ? new Date(expiresAtRaw) : null;
        const isPremium = status === 'active' && (!expiresAt || expiresAt > new Date());
        return {
            isPremium,
            status,
            plan: typeof row.subscription_plan === 'string' ? row.subscription_plan : null,
            productId: typeof row.subscription_product_id === 'string' ? row.subscription_product_id : null,
            expiresAt: expiresAtRaw,
            lastVerifiedAt: typeof row.subscription_last_verified_at === 'string' ? row.subscription_last_verified_at : null,
            transactionId: typeof row.subscription_transaction_id === 'string' ? row.subscription_transaction_id : null,
            originalTransactionId: typeof row.subscription_original_transaction_id === 'string' ? row.subscription_original_transaction_id : null,
            environment: typeof row.subscription_environment === 'string' ? row.subscription_environment : null,
        };
    }
    static async updateUserSubscriptionStatus(userId, payload) {
        const status = payload.isPremium ? 'active' : 'inactive';
        const plan = payload.plan?.trim() || null;
        const productId = payload.productId?.trim() || null;
        const expiresAt = payload.isPremium ? (payload.expiresAt ?? null) : null;
        const transactionId = payload.isPremium ? (payload.transactionId ?? null) : null;
        const originalTransactionId = payload.isPremium ? (payload.originalTransactionId ?? null) : null;
        const { error } = await exports.supabase
            .from('users')
            .update({
            subscription_status: status,
            subscription_plan: plan,
            subscription_product_id: productId,
            subscription_expires_at: expiresAt,
            subscription_last_verified_at: payload.lastVerifiedAt ?? new Date().toISOString(),
            subscription_transaction_id: transactionId,
            subscription_original_transaction_id: originalTransactionId,
            subscription_environment: payload.environment ?? null,
        })
            .eq('id', userId);
        if (error) {
            if (this.isMissingColumnError(error)) {
                console.warn('Subscription columns are missing on users table; apply migration 019_user_subscription_status.sql');
                return false;
            }
            console.error('Error updating user subscription status:', error);
            return false;
        }
        return true;
    }
    // ═══════════════════════════════════════════════════════════════
    // PROFILE OPERATIONS
    // ═══════════════════════════════════════════════════════════════
    static async saveProfile(userId, profile) {
        const { data, error } = await exports.supabase
            .from('profiles')
            .upsert({
            user_id: userId,
            skin_type: profile.skinType,
            skin_tone: profile.skinTone,
            skin_goals: profile.skinGoals,
            hair_type: profile.hairType,
            concerns: profile.concerns,
            budget: profile.budget,
            fragrance_free: profile.fragranceFree,
            wash_frequency: profile.washFrequency,
            sunscreen_usage: profile.sunscreenUsage,
            routine_reminders: profile.routineReminders,
            reminder_time: profile.reminderTime,
            photo_check_ins: profile.photoCheckIns,
            updated_at: new Date().toISOString()
        }, {
            onConflict: 'user_id'
        })
            .select()
            .single();
        if (error) {
            console.error('Error saving profile:', error);
            return null;
        }
        return data;
    }
    static async getProfileByUserId(userId) {
        const { data, error } = await exports.supabase
            .from('profiles')
            .select('*')
            .eq('user_id', userId)
            .single();
        if (error)
            return null;
        return data;
    }
    // ═══════════════════════════════════════════════════════════════
    // ROUTINE OPERATIONS
    // ═══════════════════════════════════════════════════════════════
    static async saveRoutine(userId, profileId, routineData) {
        const routineKey = await this.generateUniqueRoutineKey();
        const enrichedRoutineData = this.attachRoutineKey(routineData, routineKey);
        // Product routines are user-owned snapshots; overwrite prior routine
        // so onboarding re-runs, chat edits, and manual edits always replace
        // stale/generated routines with the latest canonical one.
        const { error: deleteError } = await exports.supabase
            .from('routines')
            .delete()
            .eq('user_id', userId);
        if (deleteError) {
            console.error('Error clearing previous routine:', deleteError);
            return null;
        }
        const insertPayload = {
            user_id: userId,
            profile_id: profileId,
            routine_data: enrichedRoutineData
        };
        let { data, error } = await exports.supabase
            .from('routines')
            .insert(insertPayload)
            .select()
            .single();
        // Backward-compat safety: some environments still have routines.profile_id
        // pointing at the legacy profiles table. Retry with null profile_id so
        // routine persistence still works until migration is applied.
        if (error && String(error.message || '').includes('routines_profile_id_fkey')) {
            console.warn('⚠️ routines.profile_id FK mismatch detected. Retrying save with null profile_id.');
            ({ data, error } = await exports.supabase
                .from('routines')
                .insert({
                user_id: userId,
                profile_id: null,
                routine_data: enrichedRoutineData
            })
                .select()
                .single());
        }
        if (error) {
            console.error('Error saving routine:', error);
            return null;
        }
        return data;
    }
    static async getRoutinesByUserId(userId) {
        const { data, error } = await exports.supabase
            .from('routines')
            .select('*')
            .eq('user_id', userId)
            .order('created_at', { ascending: false });
        if (error)
            return [];
        return data || [];
    }
    static async getLatestRoutine(userId) {
        const { data, error } = await exports.supabase
            .from('routines')
            .select('*')
            .eq('user_id', userId)
            .order('created_at', { ascending: false })
            .limit(1)
            .single();
        if (error)
            return null;
        return data;
    }
    static async getRoutineByShareKey(routineKey) {
        const normalized = this.normalizeRoutineKey(routineKey);
        if (!normalized)
            return null;
        // Primary path: query by nested JSON key.
        {
            const { data, error } = await exports.supabase
                .from('routines')
                .select('*')
                .contains('routine_data', { meta: { routine_key: normalized } })
                .order('created_at', { ascending: false })
                .limit(1)
                .maybeSingle();
            if (!error && data)
                return data;
        }
        // Backward-compat path: top-level routine_data.routine_key.
        {
            const { data, error } = await exports.supabase
                .from('routines')
                .select('*')
                .contains('routine_data', { routine_key: normalized })
                .order('created_at', { ascending: false })
                .limit(1)
                .maybeSingle();
            if (!error && data)
                return data;
        }
        // Last-resort scan for environments where JSON contains filters are limited.
        const { data: recent, error: recentError } = await exports.supabase
            .from('routines')
            .select('*')
            .order('created_at', { ascending: false })
            .limit(500);
        if (recentError || !recent)
            return null;
        return recent.find((row) => this.extractRoutineKey(row?.routine_data) === normalized) || null;
    }
    // ═══════════════════════════════════════════════════════════════
    // PRODUCT OPERATIONS
    // ═══════════════════════════════════════════════════════════════
    static async getAllProducts() {
        const { data, error } = await exports.supabase
            .from('products')
            .select('*')
            .order('rating', { ascending: false });
        if (error)
            return [];
        return data || [];
    }
    static async getProductsByCategory(category) {
        const { data, error } = await exports.supabase
            .from('products')
            .select('*')
            .eq('category', category);
        if (error)
            return [];
        return data || [];
    }
    static async searchProducts(tags) {
        const { data, error } = await exports.supabase
            .from('products')
            .select('*')
            .overlaps('tags', tags);
        if (error)
            return [];
        return data || [];
    }
    static async seedProducts(products) {
        const { error } = await exports.supabase
            .from('products')
            .upsert(products, { onConflict: 'name' });
        if (error) {
            console.error('Error seeding products:', error);
            return false;
        }
        return true;
    }
    static async getProductsByIds(ids) {
        if (!ids || ids.length === 0)
            return [];
        const { data, error } = await exports.supabase
            .from('products')
            .select('*')
            .in('id', ids);
        if (error)
            return [];
        return data || [];
    }
    // ═══════════════════════════════════════════════════════════════
    // CART OPERATIONS
    // ═══════════════════════════════════════════════════════════════
    static async getCartItems(userId) {
        const { data, error } = await exports.supabase
            .from('cart_items')
            .select('product_id, quantity, products(*)')
            .eq('user_id', userId);
        if (error) {
            console.error('Error fetching cart items:', error);
            return [];
        }
        return (data || [])
            .map((row) => ({
            product: row.products,
            quantity: row.quantity
        }))
            .filter((row) => row.product);
    }
    static async upsertCartItem(userId, productId, quantity) {
        if (quantity <= 0) {
            return this.removeCartItem(userId, productId);
        }
        const { error } = await exports.supabase
            .from('cart_items')
            .upsert({
            user_id: userId,
            product_id: productId,
            quantity
        }, { onConflict: 'user_id,product_id' });
        if (error) {
            console.error('Error upserting cart item:', error);
            return false;
        }
        return true;
    }
    static async removeCartItem(userId, productId) {
        const { error } = await exports.supabase
            .from('cart_items')
            .delete()
            .eq('user_id', userId)
            .eq('product_id', productId);
        if (error) {
            console.error('Error removing cart item:', error);
            return false;
        }
        return true;
    }
    static async clearCart(userId) {
        const { error } = await exports.supabase
            .from('cart_items')
            .delete()
            .eq('user_id', userId);
        if (error) {
            console.error('Error clearing cart:', error);
            return false;
        }
        return true;
    }
    // ═══════════════════════════════════════════════════════════════
    // SKIN PROFILE OPERATIONS
    // ═══════════════════════════════════════════════════════════════
    static async saveSkinProfile(userId, profile) {
        // Calculate skin tone label if not provided
        let skinToneLabel = profile.skinToneLabel;
        if (!skinToneLabel && profile.skinTone !== undefined) {
            const tone = profile.skinTone;
            if (tone < 0.15)
                skinToneLabel = 'fair';
            else if (tone < 0.3)
                skinToneLabel = 'light';
            else if (tone < 0.45)
                skinToneLabel = 'light-medium';
            else if (tone < 0.6)
                skinToneLabel = 'medium';
            else if (tone < 0.75)
                skinToneLabel = 'medium-deep';
            else if (tone < 0.9)
                skinToneLabel = 'deep';
            else
                skinToneLabel = 'rich-deep';
        }
        const { data, error } = await exports.supabase
            .from('skin_profiles')
            .upsert({
            user_id: userId,
            name: profile.name,
            skin_type: profile.skinType,
            skin_tone: profile.skinTone,
            skin_tone_label: skinToneLabel,
            skin_goals: profile.skinGoals,
            skin_concerns: profile.skinConcerns,
            sunscreen_usage: profile.sunscreenUsage,
            fragrance_free: profile.fragranceFree,
            hair_type: profile.hairType,
            hair_concerns: profile.hairConcerns,
            wash_frequency: profile.washFrequency,
            scalp_sensitivity: profile.scalpSensitivity,
            budget: profile.budget,
            routine_reminders: profile.routineReminders,
            reminder_time: profile.reminderTime,
            photo_check_ins: profile.photoCheckIns,
            photo_front_url: profile.photoFrontUrl,
            photo_left_url: profile.photoLeftUrl,
            photo_right_url: profile.photoRightUrl,
            photo_scalp_url: profile.photoScalpUrl,
            image_analysis: profile.imageAnalysis,
            analysis_confidence: profile.imageAnalysis?.confidence_scores?.skin_analysis,
            last_analysis_at: profile.imageAnalysis ? new Date().toISOString() : null,
            onboarding_completed: true,
            onboarding_completed_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        }, {
            onConflict: 'user_id'
        })
            .select()
            .single();
        if (error) {
            console.error('Error saving skin profile:', error);
            return null;
        }
        // Also mark user as onboarded in users table
        console.log('📝 Marking user as onboarded in users table...');
        await this.markUserOnboarded(userId);
        return data;
    }
    static async getSkinProfileByUserId(userId) {
        const { data, error } = await exports.supabase
            .from('skin_profiles')
            .select('*')
            .eq('user_id', userId)
            .single();
        if (error)
            return null;
        return data;
    }
    static async updateImageAnalysis(userId, analysis) {
        const { data, error } = await exports.supabase
            .from('skin_profiles')
            .update({
            image_analysis: analysis,
            analysis_confidence: analysis.confidence_scores?.skin_analysis,
            last_analysis_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        })
            .eq('user_id', userId)
            .select()
            .single();
        if (error) {
            console.error('Error updating image analysis:', error);
            return null;
        }
        return data;
    }
    // ═══════════════════════════════════════════════════════════════
    // PHOTO CHECK-IN OPERATIONS
    // ═══════════════════════════════════════════════════════════════
    static async savePhotoCheckIn(userId, skinProfileId, checkIn) {
        const { data, error } = await exports.supabase
            .from('photo_check_ins')
            .insert({
            user_id: userId,
            skin_profile_id: skinProfileId,
            photo_front_url: checkIn.photoFrontUrl,
            photo_left_url: checkIn.photoLeftUrl,
            photo_right_url: checkIn.photoRightUrl,
            image_analysis: checkIn.imageAnalysis,
            comparison_to_baseline: checkIn.comparisonToBaseline,
            user_notes: checkIn.userNotes,
            irritation_reported: checkIn.irritationReported,
            improvement_reported: checkIn.improvementReported
        })
            .select()
            .single();
        if (error) {
            console.error('Error saving photo check-in:', error);
            return null;
        }
        return data;
    }
    static async getPhotoCheckIns(userId) {
        const { data, error } = await exports.supabase
            .from('photo_check_ins')
            .select('*')
            .eq('user_id', userId)
            .order('created_at', { ascending: false });
        if (error)
            return [];
        return data || [];
    }
    // ═══════════════════════════════════════════════════════════════
    // CHAT OPERATIONS
    // ═══════════════════════════════════════════════════════════════
    static async createConversation(userId, title) {
        const { data, error } = await exports.supabase
            .from('chat_conversations')
            .insert({ user_id: userId, title: title || 'New Chat' })
            .select()
            .single();
        if (error) {
            console.error('Error creating conversation:', error);
            return null;
        }
        return data;
    }
    static async getConversations(userId) {
        const { data, error } = await exports.supabase
            .from('chat_conversations')
            .select('*')
            .eq('user_id', userId)
            .order('updated_at', { ascending: false });
        if (error)
            return [];
        return data || [];
    }
    static async getConversationMessages(conversationId) {
        const { data, error } = await exports.supabase
            .from('chat_messages')
            .select('*')
            .eq('conversation_id', conversationId)
            .order('created_at', { ascending: true });
        if (error)
            return [];
        return data || [];
    }
    static async saveMessage(conversationId, role, content, metadata) {
        const row = { conversation_id: conversationId, role, content };
        if (metadata)
            row.metadata = metadata;
        const { data, error } = await exports.supabase
            .from('chat_messages')
            .insert(row)
            .select()
            .single();
        if (error) {
            console.error('Error saving message:', error);
            return null;
        }
        return data;
    }
    static async updateConversationTitle(conversationId, title) {
        const { error } = await exports.supabase
            .from('chat_conversations')
            .update({ title })
            .eq('id', conversationId);
        if (error) {
            console.error('Error updating conversation title:', error);
            return false;
        }
        return true;
    }
    static async deleteConversation(conversationId) {
        // Messages cascade-delete via FK
        const { error } = await exports.supabase
            .from('chat_conversations')
            .delete()
            .eq('id', conversationId);
        if (error) {
            console.error('Error deleting conversation:', error);
            return false;
        }
        return true;
    }
    static async getLatestInsightByUserId(userId) {
        const { data, error } = await exports.supabase
            .from('skin_insights')
            .select('*')
            .eq('user_id', userId)
            .order('created_at', { ascending: false })
            .limit(1);
        if (error) {
            console.error('Error fetching insights:', error);
            return null;
        }
        return data && data.length > 0 ? data[0] : null;
    }
    static async saveInsight(userId, insight) {
        // Get current streaks to include in insight
        const streaks = await this.getStreaks(userId);
        const { data, error } = await exports.supabase
            .from('skin_insights')
            .insert({
            user_id: userId,
            skin_score: insight.skinScore ?? null,
            hydration: insight.hydration ?? null,
            protection: insight.protection ?? null,
            texture: insight.texture ?? null,
            notes: insight.notes ?? null,
            source: insight.source ?? 'app',
            morning_streak: streaks.morning,
            evening_streak: streaks.evening,
            longest_morning_streak: insight.longestMorningStreak ?? streaks.morning,
            longest_evening_streak: insight.longestEveningStreak ?? streaks.evening,
        })
            .select()
            .single();
        if (error) {
            console.error('Error saving insights:', error);
            return null;
        }
        return data;
    }
    static async updateInsightStreaks(userId) {
        // Update the latest insight with current streaks
        const streaks = await this.getStreaks(userId);
        const { data: latest } = await exports.supabase
            .from('skin_insights')
            .select('id')
            .eq('user_id', userId)
            .order('created_at', { ascending: false })
            .limit(1)
            .single();
        if (latest) {
            await exports.supabase
                .from('skin_insights')
                .update({
                morning_streak: streaks.morning,
                evening_streak: streaks.evening,
            })
                .eq('id', latest.id);
        }
    }
    // ── Routine Check-ins ──────────────────────────────────────────
    static async getTodayCheckins(userId, date) {
        const checkDate = date || new Date().toISOString().split('T')[0];
        const { data, error } = await exports.supabase
            .from('routine_checkins')
            .select('routine_type, step_id')
            .eq('user_id', userId)
            .eq('completed_at', checkDate);
        if (error) {
            console.error('Error fetching check-ins:', error);
            return new Set();
        }
        // Return set of "routine_type:step_id" keys
        return new Set((data || []).map((c) => `${c.routine_type}:${c.step_id}`));
    }
    static async markStepComplete(userId, routineType, stepId, stepName, date) {
        const checkDate = date || new Date().toISOString().split('T')[0];
        const { error } = await exports.supabase
            .from('routine_checkins')
            .upsert({
            user_id: userId,
            routine_type: routineType,
            step_id: stepId,
            step_name: stepName,
            completed_at: checkDate,
        }, {
            onConflict: 'user_id,routine_type,step_id,completed_at'
        });
        if (error) {
            console.error('Error marking step complete:', error);
            return false;
        }
        // Update streak
        await this.updateStreak(userId, routineType, checkDate);
        return true;
    }
    static async markStepIncomplete(userId, routineType, stepId, date) {
        const checkDate = date || new Date().toISOString().split('T')[0];
        const { error } = await exports.supabase
            .from('routine_checkins')
            .delete()
            .eq('user_id', userId)
            .eq('routine_type', routineType)
            .eq('step_id', stepId)
            .eq('completed_at', checkDate);
        if (error) {
            console.error('Error marking step incomplete:', error);
            return false;
        }
        // Update streak
        await this.updateStreak(userId, routineType, checkDate);
        return true;
    }
    static async getStreaks(userId) {
        const { data, error } = await exports.supabase
            .from('routine_streaks')
            .select('routine_type, current_streak')
            .eq('user_id', userId);
        if (error) {
            console.error('Error fetching streaks:', error);
            return { morning: 0, evening: 0 };
        }
        const streaks = { morning: 0, evening: 0 };
        (data || []).forEach((s) => {
            if (s.routine_type === 'morning')
                streaks.morning = s.current_streak || 0;
            if (s.routine_type === 'evening')
                streaks.evening = s.current_streak || 0;
        });
        return streaks;
    }
    static async updateStreak(userId, routineType, date) {
        // Get all check-ins for this routine type today
        const { data: todayCheckins } = await exports.supabase
            .from('routine_checkins')
            .select('step_id')
            .eq('user_id', userId)
            .eq('routine_type', routineType)
            .eq('completed_at', date);
        // Get routine steps count (we'll need to fetch from routine_data or pass it)
        // For now, assume if all steps are checked, routine is complete
        const allStepsComplete = (todayCheckins?.length || 0) > 0; // Simplified - should check against actual step count
        // Get current streak
        const { data: streakData } = await exports.supabase
            .from('routine_streaks')
            .select('*')
            .eq('user_id', userId)
            .eq('routine_type', routineType)
            .single();
        const today = new Date(date);
        const yesterday = new Date(today);
        yesterday.setDate(yesterday.getDate() - 1);
        const yesterdayStr = yesterday.toISOString().split('T')[0];
        let currentStreak = streakData?.current_streak || 0;
        let longestStreak = streakData?.longest_streak || 0;
        const lastCompleted = streakData?.last_completed_date ? new Date(streakData.last_completed_date) : null;
        if (allStepsComplete) {
            // Check if this continues the streak
            if (lastCompleted && lastCompleted.toISOString().split('T')[0] === yesterdayStr) {
                // Continue streak
                currentStreak = (currentStreak || 0) + 1;
            }
            else if (!lastCompleted || lastCompleted.toISOString().split('T')[0] !== date) {
                // New streak
                currentStreak = 1;
            }
            longestStreak = Math.max(longestStreak, currentStreak);
            await exports.supabase
                .from('routine_streaks')
                .upsert({
                user_id: userId,
                routine_type: routineType,
                current_streak: currentStreak,
                longest_streak: longestStreak,
                last_completed_date: date,
                updated_at: new Date().toISOString(),
            }, {
                onConflict: 'user_id,routine_type'
            });
        }
        else {
            // Check if streak should be broken (no steps completed today)
            const { data: anyToday } = await exports.supabase
                .from('routine_checkins')
                .select('id')
                .eq('user_id', userId)
                .eq('routine_type', routineType)
                .eq('completed_at', date)
                .limit(1);
            if (!anyToday || anyToday.length === 0) {
                // No steps completed today - reset streak if it was active
                if (lastCompleted && lastCompleted.toISOString().split('T')[0] !== date) {
                    await exports.supabase
                        .from('routine_streaks')
                        .upsert({
                        user_id: userId,
                        routine_type: routineType,
                        current_streak: 0,
                        longest_streak: longestStreak,
                        last_completed_date: null,
                        updated_at: new Date().toISOString(),
                    }, {
                        onConflict: 'user_id,routine_type'
                    });
                }
            }
        }
    }
}
exports.DatabaseService = DatabaseService;
DatabaseService.ROUTINE_KEY_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
exports.default = exports.supabase;
