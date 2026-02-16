"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.RecommendationAgent = void 0;
const catalog_1 = require("../data/catalog");
class RecommendationAgent {
    findProduct(category, tags, excludeTags = []) {
        return catalog_1.CATALOG.find(p => {
            if (p.category !== category)
                return false;
            // Must match at least one positive tag if provided, 
            // but for simplicity in this MVP, let's just score them.
            const hasExcluded = excludeTags.some(t => p.tags.includes(t));
            if (hasExcluded)
                return false;
            // Simple matching: just return the first one that matches basic criteria
            // In a real agent, this would be a ranked retrieval.
            const matchesTags = tags.every(t => p.tags.includes(t));
            // Relaxed matching if strict fails
            if (matchesTags)
                return true;
            return false;
        }) || catalog_1.CATALOG.find(p => p.category === category); // Fallback to any in category
    }
    async generateRoutine(profile) {
        const amSteps = [];
        const pmSteps = [];
        const hairSteps = [];
        // --- Skincare ---
        // 1. Cleanser
        let cleanserTags = [];
        if (profile.skinType === 'oily')
            cleanserTags.push('oily-skin');
        if (profile.skinType === 'dry')
            cleanserTags.push('dry-skin');
        if (profile.concerns.includes('acne'))
            cleanserTags.push('acne');
        if (profile.concerns.includes('sensitivity') || profile.fragranceFree)
            cleanserTags.push('fragrance-free');
        const cleanser = this.findProduct('cleanser', cleanserTags);
        if (cleanser) {
            amSteps.push({
                stepName: 'Cleanse',
                product: cleanser,
                instruction: 'Wash face with lukewarm water.',
                frequency: 'daily',
                timeOfDay: 'AM'
            });
            pmSteps.push({
                stepName: 'Cleanse',
                product: cleanser,
                instruction: 'Massage onto damp skin for 60 seconds.',
                frequency: 'daily',
                timeOfDay: 'PM'
            });
        }
        // 2. Treatment (PM only usually)
        if (profile.concerns.includes('acne') || profile.concerns.includes('oiliness')) {
            const treatment = this.findProduct('treatment', ['acne', 'oiliness']);
            if (treatment) {
                pmSteps.push({
                    stepName: 'Treat',
                    product: treatment,
                    instruction: 'Apply a thin layer to affected areas.',
                    frequency: 'daily',
                    timeOfDay: 'PM'
                });
            }
        }
        else if (profile.concerns.includes('aging')) {
            const retinol = this.findProduct('treatment', ['retinol']);
            if (retinol) {
                pmSteps.push({
                    stepName: 'Treat',
                    product: retinol,
                    instruction: 'Start 2x/week and build up to nightly.',
                    frequency: '2-3x/week',
                    timeOfDay: 'PM'
                });
            }
        }
        // 3. Moisturizer
        let moisturizerTags = [];
        if (profile.skinType === 'oily')
            moisturizerTags.push('oily-skin');
        if (profile.skinType === 'dry')
            moisturizerTags.push('dry-skin');
        if (profile.fragranceFree)
            moisturizerTags.push('fragrance-free');
        const moisturizer = this.findProduct('moisturizer', moisturizerTags);
        if (moisturizer) {
            amSteps.push({
                stepName: 'Moisturize',
                product: moisturizer,
                instruction: 'Apply to face and neck.',
                frequency: 'daily',
                timeOfDay: 'AM'
            });
            pmSteps.push({
                stepName: 'Moisturize',
                product: moisturizer,
                instruction: 'Apply generously to lock in hydration.',
                frequency: 'daily',
                timeOfDay: 'PM'
            });
        }
        // 4. Sunscreen (AM only)
        let spfTags = [];
        if (profile.concerns.includes('acne'))
            spfTags.push('acne');
        if (profile.fragranceFree)
            spfTags.push('fragrance-free');
        const spf = this.findProduct('sunscreen', spfTags);
        if (spf) {
            amSteps.push({
                stepName: 'Protect',
                product: spf,
                instruction: 'Apply as the last step of your morning routine.',
                frequency: 'daily',
                timeOfDay: 'AM'
            });
        }
        // --- Haircare ---
        // Shampoo
        let hairTags = [];
        if (profile.hairType === 'curly' || profile.hairType === 'coily')
            hairTags.push('curly');
        if (profile.concerns.includes('damage'))
            hairTags.push('damage');
        const shampoo = this.findProduct('shampoo', hairTags);
        if (shampoo) {
            hairSteps.push({
                stepName: 'Wash',
                product: shampoo,
                instruction: profile.concerns.includes('oiliness') ? 'Wash every other day.' : 'Wash 2-3 times a week.',
                frequency: '2-3x/week',
                timeOfDay: 'Any'
            });
        }
        // Styling
        if (profile.concerns.includes('frizz') || profile.hairType !== 'straight') {
            const styling = this.findProduct('styling', ['frizz']);
            if (styling) {
                hairSteps.push({
                    stepName: 'Style',
                    product: styling,
                    instruction: 'Apply to damp hair.',
                    frequency: 'daily',
                    timeOfDay: 'Any'
                });
            }
        }
        return {
            skincareAM: amSteps,
            skincarePM: pmSteps,
            haircare: hairSteps,
            explanation: `Based on your ${profile.skinType} skin and ${profile.concerns.join(', ')} concerns, we've focused on gentle hydration and targeted treatments.`
        };
    }
}
exports.RecommendationAgent = RecommendationAgent;
