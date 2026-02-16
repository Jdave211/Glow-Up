export type SkinType = 'oily' | 'dry' | 'combination' | 'normal' | 'sensitive';
export type HairType = 'straight' | 'wavy' | 'curly' | 'coily';
export type Concern = 'acne' | 'aging' | 'dryness' | 'oiliness' | 'pigmentation' | 'sensitivity' | 'frizz' | 'damage' | 'scalp_itch';

export interface UserProfile {
  name: string;
  age?: number;
  skinType: SkinType;
  hairType: HairType;
  concerns: Concern[];
  budget: 'low' | 'medium' | 'high';
  fragranceFree: boolean;
  location?: string; // For availability checking
}

export interface Product {
  id: string;
  name: string;
  brand: string;
  price: number;
  currency: string;
  category: 'cleanser' | 'moisturizer' | 'sunscreen' | 'treatment' | 'shampoo' | 'conditioner' | 'styling' | 'tool';
  description: string;
  imageUrl?: string;
  tags: string[]; // e.g., "contains-retinol", "sulfate-free"
  buyLink: string;
  retailer: 'Sephora' | 'Amazon' | 'Ulta' | 'Generic';
}

export interface RoutineStep {
  stepName: string; // e.g., "Cleanse", "Treat"
  product?: Product; // The recommended product
  instruction: string; // "Apply a dime-sized amount..."
  frequency: 'daily' | 'weekly' | '2-3x/week';
  timeOfDay?: 'AM' | 'PM' | 'Any';
}

export interface FullRoutine {
  skincareAM: RoutineStep[];
  skincarePM: RoutineStep[];
  haircare: RoutineStep[];
  explanation: string; // "Why this routine works for you"
}

export interface CartItem {
  product: Product;
  quantity: number;
}

export interface ShoppingCart {
  items: CartItem[];
  totalPrice: number;
  currency: string;
  retailerLinks: {
    retailer: string;
    cartUrl: string; // Direct link to pre-filled cart if possible, or product page
  }[];
}

