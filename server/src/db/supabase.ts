import { createClient, SupabaseClient } from '@supabase/supabase-js';

// Supabase Configuration
const supabaseUrl = 'https://ukhxwxmqjltfjugizbku.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVraHh3eG1xamx0Zmp1Z2l6Ymt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1NDA2NTUsImV4cCI6MjA4NTExNjY1NX0.x8sfd80Hmb6_wLtBG0Up9OqQZ49wjrhTE_wfdkVnPk4';

export const supabase: SupabaseClient = createClient(supabaseUrl, supabaseAnonKey);

// Database types
export interface DbUser {
  id: string;
  email: string;
  name: string;
  onboarded: boolean;
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

// Skin Profile - Complete onboarding data
export interface DbSkinProfile {
  id: string;
  user_id: string;
  name?: string;
  
  // Skin
  skin_type: string;
  skin_tone?: number;
  skin_tone_label?: string;
  skin_goals?: string[];
  skin_concerns?: string[];
  sunscreen_usage?: string;
  fragrance_free?: boolean;
  
  // Hair
  hair_type: string;
  hair_concerns?: string[];
  wash_frequency?: string;
  scalp_sensitivity?: boolean;
  
  // Lifestyle
  budget?: string;
  routine_reminders?: boolean;
  reminder_time?: string;
  photo_check_ins?: boolean;
  
  // Photos
  photo_front_url?: string;
  photo_left_url?: string;
  photo_right_url?: string;
  photo_scalp_url?: string;
  
  // Image Analysis
  image_analysis?: ImageAnalysisResult;
  analysis_confidence?: number;
  last_analysis_at?: string;
  
  // Meta
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

// Database service functions
export class DatabaseService {
  // ═══════════════════════════════════════════════════════════════
  // USER OPERATIONS
  // ═══════════════════════════════════════════════════════════════
  
  static async createUser(email: string, name: string): Promise<DbUser | null> {
    const { data, error } = await supabase
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

  static async getUserByEmail(email: string): Promise<DbUser | null> {
    const { data, error } = await supabase
      .from('users')
      .select('*')
      .eq('email', email)
      .single();
    
    if (error) return null;
    return data;
  }

  static async getOrCreateUser(email: string, name: string): Promise<DbUser | null> {
    let user = await this.getUserByEmail(email);
    if (!user) {
      user = await this.createUser(email, name);
    }
    return user;
  }

  static async getUserById(userId: string): Promise<DbUser | null> {
    const { data, error } = await supabase
      .from('users')
      .select('*')
      .eq('id', userId)
      .single();
    
    if (error) return null;
    return data;
  }

  static async markUserOnboarded(userId: string): Promise<boolean> {
    console.log('🔄 Attempting to mark user onboarded:', userId);
    
    const { data, error } = await supabase
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

  static async isUserOnboarded(userId: string): Promise<boolean> {
    const { data, error } = await supabase
      .from('users')
      .select('onboarded')
      .eq('id', userId)
      .single();
    
    if (error) return false;
    return data?.onboarded === true;
  }

  // ═══════════════════════════════════════════════════════════════
  // PROFILE OPERATIONS
  // ═══════════════════════════════════════════════════════════════
  
  static async saveProfile(
    userId: string,
    profile: {
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
    }
  ): Promise<DbProfile | null> {
    const { data, error } = await supabase
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

  static async getProfileByUserId(userId: string): Promise<DbProfile | null> {
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('user_id', userId)
      .single();
    
    if (error) return null;
    return data;
  }

  // ═══════════════════════════════════════════════════════════════
  // ROUTINE OPERATIONS
  // ═══════════════════════════════════════════════════════════════
  
  static async saveRoutine(
    userId: string,
    profileId: string,
    routineData: any
  ): Promise<DbRoutine | null> {
    const { data, error } = await supabase
      .from('routines')
      .insert({
        user_id: userId,
        profile_id: profileId,
        routine_data: routineData
      })
      .select()
      .single();
    
    if (error) {
      console.error('Error saving routine:', error);
      return null;
    }
    return data;
  }

  static async getRoutinesByUserId(userId: string): Promise<DbRoutine[]> {
    const { data, error } = await supabase
      .from('routines')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false });
    
    if (error) return [];
    return data || [];
  }

  static async getLatestRoutine(userId: string): Promise<DbRoutine | null> {
    const { data, error } = await supabase
      .from('routines')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(1)
      .single();
    
    if (error) return null;
    return data;
  }

  // ═══════════════════════════════════════════════════════════════
  // PRODUCT OPERATIONS
  // ═══════════════════════════════════════════════════════════════
  
  static async getAllProducts(): Promise<DbProduct[]> {
    const { data, error } = await supabase
      .from('products')
      .select('*')
      .order('rating', { ascending: false });
    
    if (error) return [];
    return data || [];
  }

  static async getProductsByCategory(category: string): Promise<DbProduct[]> {
    const { data, error } = await supabase
      .from('products')
      .select('*')
      .eq('category', category);
    
    if (error) return [];
    return data || [];
  }

  static async searchProducts(tags: string[]): Promise<DbProduct[]> {
    const { data, error } = await supabase
      .from('products')
      .select('*')
      .overlaps('tags', tags);
    
    if (error) return [];
    return data || [];
  }

  static async seedProducts(products: Omit<DbProduct, 'id' | 'created_at'>[]): Promise<boolean> {
    const { error } = await supabase
      .from('products')
      .upsert(products, { onConflict: 'name' });
    
    if (error) {
      console.error('Error seeding products:', error);
      return false;
    }
    return true;
  }

  static async getProductsByIds(ids: string[]): Promise<DbProduct[]> {
    if (!ids || ids.length === 0) return [];
    const { data, error } = await supabase
      .from('products')
      .select('*')
      .in('id', ids);
    
    if (error) return [];
    return data || [];
  }

  // ═══════════════════════════════════════════════════════════════
  // CART OPERATIONS
  // ═══════════════════════════════════════════════════════════════

  static async getCartItems(userId: string): Promise<{ product: DbProduct; quantity: number }[]> {
    const { data, error } = await supabase
      .from('cart_items')
      .select('product_id, quantity, products(*)')
      .eq('user_id', userId);
    
    if (error) {
      console.error('Error fetching cart items:', error);
      return [];
    }
    
    return (data || [])
      .map((row: any) => ({
        product: row.products,
        quantity: row.quantity
      }))
      .filter((row: any) => row.product);
  }

  static async upsertCartItem(userId: string, productId: string, quantity: number): Promise<boolean> {
    if (quantity <= 0) {
      return this.removeCartItem(userId, productId);
    }
    const { error } = await supabase
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

  static async removeCartItem(userId: string, productId: string): Promise<boolean> {
    const { error } = await supabase
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

  static async clearCart(userId: string): Promise<boolean> {
    const { error } = await supabase
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
  
  static async saveSkinProfile(
    userId: string,
    profile: {
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
    }
  ): Promise<DbSkinProfile | null> {
    // Calculate skin tone label if not provided
    let skinToneLabel = profile.skinToneLabel;
    if (!skinToneLabel && profile.skinTone !== undefined) {
      const tone = profile.skinTone;
      if (tone < 0.15) skinToneLabel = 'fair';
      else if (tone < 0.3) skinToneLabel = 'light';
      else if (tone < 0.45) skinToneLabel = 'light-medium';
      else if (tone < 0.6) skinToneLabel = 'medium';
      else if (tone < 0.75) skinToneLabel = 'medium-deep';
      else if (tone < 0.9) skinToneLabel = 'deep';
      else skinToneLabel = 'rich-deep';
    }

    const { data, error } = await supabase
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

  static async getSkinProfileByUserId(userId: string): Promise<DbSkinProfile | null> {
    const { data, error } = await supabase
      .from('skin_profiles')
      .select('*')
      .eq('user_id', userId)
      .single();
    
    if (error) return null;
    return data;
  }

  static async updateImageAnalysis(
    userId: string, 
    analysis: ImageAnalysisResult
  ): Promise<DbSkinProfile | null> {
    const { data, error } = await supabase
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
  
  static async savePhotoCheckIn(
    userId: string,
    skinProfileId: string,
    checkIn: {
      photoFrontUrl?: string;
      photoLeftUrl?: string;
      photoRightUrl?: string;
      imageAnalysis?: any;
      comparisonToBaseline?: any;
      userNotes?: string;
      irritationReported?: boolean;
      improvementReported?: boolean;
    }
  ): Promise<DbPhotoCheckIn | null> {
    const { data, error } = await supabase
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

  static async getPhotoCheckIns(userId: string): Promise<DbPhotoCheckIn[]> {
    const { data, error } = await supabase
      .from('photo_check_ins')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false });
    
    if (error) return [];
    return data || [];
  }

  // ═══════════════════════════════════════════════════════════════
  // CHAT OPERATIONS
  // ═══════════════════════════════════════════════════════════════

  static async createConversation(userId: string, title?: string): Promise<any | null> {
    const { data, error } = await supabase
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

  static async getConversations(userId: string): Promise<any[]> {
    const { data, error } = await supabase
      .from('chat_conversations')
      .select('*')
      .eq('user_id', userId)
      .order('updated_at', { ascending: false });
    
    if (error) return [];
    return data || [];
  }

  static async getConversationMessages(conversationId: string): Promise<any[]> {
    const { data, error } = await supabase
      .from('chat_messages')
      .select('*')
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: true });
    
    if (error) return [];
    return data || [];
  }

  static async saveMessage(conversationId: string, role: string, content: string, metadata?: any): Promise<any | null> {
    const row: any = { conversation_id: conversationId, role, content };
    if (metadata) row.metadata = metadata;
    const { data, error } = await supabase
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

  static async updateConversationTitle(conversationId: string, title: string): Promise<boolean> {
    const { error } = await supabase
      .from('chat_conversations')
      .update({ title })
      .eq('id', conversationId);
    
    if (error) {
      console.error('Error updating conversation title:', error);
      return false;
    }
    return true;
  }

  static async deleteConversation(conversationId: string): Promise<boolean> {
    // Messages cascade-delete via FK
    const { error } = await supabase
      .from('chat_conversations')
      .delete()
      .eq('id', conversationId);
    
    if (error) {
      console.error('Error deleting conversation:', error);
      return false;
    }
    return true;
  }

  static async getLatestInsightByUserId(userId: string): Promise<any | null> {
    const { data, error } = await supabase
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

  static async saveInsight(userId: string, insight: any): Promise<any | null> {
    // Get current streaks to include in insight
    const streaks = await this.getStreaks(userId);
    
    const { data, error } = await supabase
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
  
  static async updateInsightStreaks(userId: string): Promise<void> {
    // Update the latest insight with current streaks
    const streaks = await this.getStreaks(userId);
    const { data: latest } = await supabase
      .from('skin_insights')
      .select('id')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(1)
      .single();
    
    if (latest) {
      await supabase
        .from('skin_insights')
        .update({
          morning_streak: streaks.morning,
          evening_streak: streaks.evening,
        })
        .eq('id', latest.id);
    }
  }

  // ── Routine Check-ins ──────────────────────────────────────────
  static async getTodayCheckins(userId: string, date?: string): Promise<Set<string>> {
    const checkDate = date || new Date().toISOString().split('T')[0];
    const { data, error } = await supabase
      .from('routine_checkins')
      .select('routine_type, step_id')
      .eq('user_id', userId)
      .eq('completed_at', checkDate);
    
    if (error) {
      console.error('Error fetching check-ins:', error);
      return new Set();
    }
    
    // Return set of "routine_type:step_id" keys
    return new Set((data || []).map((c: any) => `${c.routine_type}:${c.step_id}`));
  }

  static async markStepComplete(userId: string, routineType: string, stepId: string, stepName: string, date?: string): Promise<boolean> {
    const checkDate = date || new Date().toISOString().split('T')[0];
    const { error } = await supabase
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

  static async markStepIncomplete(userId: string, routineType: string, stepId: string, date?: string): Promise<boolean> {
    const checkDate = date || new Date().toISOString().split('T')[0];
    const { error } = await supabase
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

  static async getStreaks(userId: string): Promise<{ morning: number; evening: number }> {
    const { data, error } = await supabase
      .from('routine_streaks')
      .select('routine_type, current_streak')
      .eq('user_id', userId);
    
    if (error) {
      console.error('Error fetching streaks:', error);
      return { morning: 0, evening: 0 };
    }
    
    const streaks: { morning: number; evening: number } = { morning: 0, evening: 0 };
    (data || []).forEach((s: any) => {
      if (s.routine_type === 'morning') streaks.morning = s.current_streak || 0;
      if (s.routine_type === 'evening') streaks.evening = s.current_streak || 0;
    });
    
    return streaks;
  }

  private static async updateStreak(userId: string, routineType: string, date: string): Promise<void> {
    // Get all check-ins for this routine type today
    const { data: todayCheckins } = await supabase
      .from('routine_checkins')
      .select('step_id')
      .eq('user_id', userId)
      .eq('routine_type', routineType)
      .eq('completed_at', date);
    
    // Get routine steps count (we'll need to fetch from routine_data or pass it)
    // For now, assume if all steps are checked, routine is complete
    const allStepsComplete = (todayCheckins?.length || 0) > 0; // Simplified - should check against actual step count
    
    // Get current streak
    const { data: streakData } = await supabase
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
      } else if (!lastCompleted || lastCompleted.toISOString().split('T')[0] !== date) {
        // New streak
        currentStreak = 1;
      }
      
      longestStreak = Math.max(longestStreak, currentStreak);
      
      await supabase
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
    } else {
      // Check if streak should be broken (no steps completed today)
      const { data: anyToday } = await supabase
        .from('routine_checkins')
        .select('id')
        .eq('user_id', userId)
        .eq('routine_type', routineType)
        .eq('completed_at', date)
        .limit(1);
      
      if (!anyToday || anyToday.length === 0) {
        // No steps completed today - reset streak if it was active
        if (lastCompleted && lastCompleted.toISOString().split('T')[0] !== date) {
          await supabase
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

export default supabase;

