import { SupabaseClient } from '@supabase/supabase-js';
export declare const supabase: SupabaseClient;
export interface DbUser {
    id: string;
    email: string;
    name: string;
    onboarded: boolean;
    is_premium?: boolean;
    stripe_customer_id?: string;
    created_at: string;
}
export interface DbProfile {
    id: string;
    user_id: string;
    skin_type: string;
    skin_tone?: number;
    skin_goals?: string[];
    hair_type: string;
    concerns: string[];
    budget: string;
    fragrance_free: boolean;
    wash_frequency?: string;
    sunscreen_usage?: string;
    routine_reminders?: boolean;
    reminder_time?: string;
    photo_check_ins?: boolean;
    created_at: string;
    updated_at: string;
}
export interface DbRoutine {
    id: string;
    user_id: string;
    profile_id: string;
    routine_data: any;
    created_at: string;
}
export interface DbProduct {
    id: string;
    name: string;
    brand: string;
    price: number;
    category: string;
    description: string;
    image_url: string | null;
    tags: string[];
    buy_link: string;
    retailer: string;
    rating: number;
    created_at: string;
}
export interface DbSkinProfile {
    id: string;
    user_id: string;
    name?: string;
    skin_type: string;
    skin_tone?: number;
    skin_tone_label?: string;
    skin_goals?: string[];
    skin_concerns?: string[];
    sunscreen_usage?: string;
    fragrance_free?: boolean;
    hair_type: string;
    hair_concerns?: string[];
    wash_frequency?: string;
    scalp_sensitivity?: boolean;
    budget?: string;
    routine_reminders?: boolean;
    reminder_time?: string;
    photo_check_ins?: boolean;
    photo_front_url?: string;
    photo_left_url?: string;
    photo_right_url?: string;
    photo_scalp_url?: string;
    image_analysis?: ImageAnalysisResult;
    analysis_confidence?: number;
    last_analysis_at?: string;
    onboarding_completed?: boolean;
    onboarding_completed_at?: string;
    created_at: string;
    updated_at: string;
}
export interface ImageAnalysisResult {
    analyzed_at: string;
    model_version: string;
    skin?: {
        detected_tone?: string;
        detected_type?: string;
        oiliness_score?: number;
        hydration_score?: number;
        texture_score?: number;
        concerns_detected?: string[];
        redness_areas?: string[];
        pore_visibility?: string;
    };
    hair?: {
        detected_type?: string;
        frizz_level?: string;
        damage_indicators?: string[];
        scalp_condition?: string;
    };
    confidence_scores?: {
        skin_analysis?: number;
        hair_analysis?: number;
    };
    recommendations_from_analysis?: string[];
}
export interface DbPhotoCheckIn {
    id: string;
    user_id: string;
    skin_profile_id: string;
    photo_front_url?: string;
    photo_left_url?: string;
    photo_right_url?: string;
    image_analysis?: any;
    comparison_to_baseline?: any;
    user_notes?: string;
    irritation_reported?: boolean;
    improvement_reported?: boolean;
    created_at: string;
}
export declare class DatabaseService {
    static createUser(email: string, name: string): Promise<DbUser | null>;
    static getUserByEmail(email: string): Promise<DbUser | null>;
    static getOrCreateUser(email: string, name: string): Promise<DbUser | null>;
    static getUserById(userId: string): Promise<DbUser | null>;
    static markUserOnboarded(userId: string): Promise<boolean>;
    static markUserPremium(userId: string, isPremium: boolean, stripeCustomerId?: string): Promise<boolean>;
    static isUserOnboarded(userId: string): Promise<boolean>;
    static saveProfile(userId: string, profile: {
        skinType: string;
        skinTone?: number;
        skinGoals?: string[];
        hairType: string;
        concerns: string[];
        budget: string;
        fragranceFree: boolean;
        washFrequency?: string;
        sunscreenUsage?: string;
        routineReminders?: boolean;
        reminderTime?: string;
        photoCheckIns?: boolean;
    }): Promise<DbProfile | null>;
    static getProfileByUserId(userId: string): Promise<DbProfile | null>;
    static saveRoutine(userId: string, profileId: string, routineData: any): Promise<DbRoutine | null>;
    static getRoutinesByUserId(userId: string): Promise<DbRoutine[]>;
    static getLatestRoutine(userId: string): Promise<DbRoutine | null>;
    static getAllProducts(): Promise<DbProduct[]>;
    static getProductsByCategory(category: string): Promise<DbProduct[]>;
    static searchProducts(tags: string[]): Promise<DbProduct[]>;
    static seedProducts(products: Omit<DbProduct, 'id' | 'created_at'>[]): Promise<boolean>;
    static getProductsByIds(ids: string[]): Promise<DbProduct[]>;
    static getCartItems(userId: string): Promise<{
        product: DbProduct;
        quantity: number;
    }[]>;
    static upsertCartItem(userId: string, productId: string, quantity: number): Promise<boolean>;
    static removeCartItem(userId: string, productId: string): Promise<boolean>;
    static clearCart(userId: string): Promise<boolean>;
    static saveSkinProfile(userId: string, profile: {
        name?: string;
        skinType: string;
        skinTone?: number;
        skinToneLabel?: string;
        skinGoals?: string[];
        skinConcerns?: string[];
        sunscreenUsage?: string;
        fragranceFree?: boolean;
        hairType: string;
        hairConcerns?: string[];
        washFrequency?: string;
        scalpSensitivity?: boolean;
        budget?: string;
        routineReminders?: boolean;
        reminderTime?: string;
        photoCheckIns?: boolean;
        photoFrontUrl?: string;
        photoLeftUrl?: string;
        photoRightUrl?: string;
        photoScalpUrl?: string;
        imageAnalysis?: ImageAnalysisResult;
    }): Promise<DbSkinProfile | null>;
    static getSkinProfileByUserId(userId: string): Promise<DbSkinProfile | null>;
    static updateImageAnalysis(userId: string, analysis: ImageAnalysisResult): Promise<DbSkinProfile | null>;
    static savePhotoCheckIn(userId: string, skinProfileId: string, checkIn: {
        photoFrontUrl?: string;
        photoLeftUrl?: string;
        photoRightUrl?: string;
        imageAnalysis?: any;
        comparisonToBaseline?: any;
        userNotes?: string;
        irritationReported?: boolean;
        improvementReported?: boolean;
    }): Promise<DbPhotoCheckIn | null>;
    static getPhotoCheckIns(userId: string): Promise<DbPhotoCheckIn[]>;
    static createConversation(userId: string, title?: string): Promise<any | null>;
    static getConversations(userId: string): Promise<any[]>;
    static getConversationMessages(conversationId: string): Promise<any[]>;
    static saveMessage(conversationId: string, role: string, content: string, metadata?: any): Promise<any | null>;
    static updateConversationTitle(conversationId: string, title: string): Promise<boolean>;
    static deleteConversation(conversationId: string): Promise<boolean>;
    static getLatestInsightByUserId(userId: string): Promise<any | null>;
    static saveInsight(userId: string, insight: any): Promise<any | null>;
    static updateInsightStreaks(userId: string): Promise<void>;
    static getTodayCheckins(userId: string, date?: string): Promise<Set<string>>;
    static markStepComplete(userId: string, routineType: string, stepId: string, stepName: string, date?: string): Promise<boolean>;
    static markStepIncomplete(userId: string, routineType: string, stepId: string, date?: string): Promise<boolean>;
    static getStreaks(userId: string): Promise<{
        morning: number;
        evening: number;
    }>;
    private static updateStreak;
}
export default supabase;
//# sourceMappingURL=supabase.d.ts.map