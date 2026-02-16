export interface UserProfileForInference {
    skinType: string;
    skinTone?: number;
    skinGoals?: string[];
    skinConcerns?: string[];
    hairType?: string;
    hairConcerns?: string[];
    washFrequency?: string;
    sunscreenUsage?: string;
    budget?: string;
    fragranceFree?: boolean;
}
export interface ProductMatch {
    id: string;
    name: string;
    brand: string;
    price: number;
    category: string;
    description: string;
    image_url: string | null;
    rating: number;
    similarity: number;
    relevance_reason?: string;
    buy_link?: string | null;
}
export interface InferenceResult {
    products: ProductMatch[];
    routine: {
        morning: RoutineStep[];
        evening: RoutineStep[];
        weekly: RoutineStep[];
    };
    summary: string;
    personalized_tips: string[];
}
export interface RoutineStep {
    step: number;
    name: string;
    product?: ProductMatch;
    instructions: string;
    frequency: string;
}
/**
 * Main inference function - takes user profile and returns personalized recommendations
 */
export declare function runInference(profile: UserProfileForInference): Promise<InferenceResult>;
/**
 * Check if LLM inference is available
 */
export declare function isLLMAvailable(): boolean;
/**
 * Create the Postgres function for vector similarity search
 * Run this once to set up the function
 */
export declare const MATCH_PRODUCTS_FUNCTION = "\nCREATE OR REPLACE FUNCTION match_products(\n  query_embedding vector(1536),\n  match_threshold float DEFAULT 0.3,\n  match_count int DEFAULT 10\n)\nRETURNS TABLE (\n  id uuid,\n  name text,\n  brand text,\n  price numeric,\n  category text,\n  description text,\n  image_url text,\n  rating numeric,\n  similarity float\n)\nLANGUAGE plpgsql\nAS $$\nBEGIN\n  RETURN QUERY\n  SELECT\n    p.id,\n    p.name,\n    p.brand,\n    p.price,\n    p.category,\n    p.description,\n    p.image_url,\n    p.rating,\n    1 - (p.embedding <=> query_embedding) as similarity\n  FROM products p\n  WHERE p.embedding IS NOT NULL\n    AND 1 - (p.embedding <=> query_embedding) > match_threshold\n  ORDER BY similarity DESC\n  LIMIT match_count;\nEND;\n$$;\n";
//# sourceMappingURL=index.d.ts.map