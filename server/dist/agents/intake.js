"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.IntakeAgent = void 0;
class IntakeAgent {
    async analyze(formData) {
        // In a real app, this would process images using Vision API
        // and merge findings with form data.
        // For now, we just validate and structure the form data.
        const profile = {
            name: formData.name || 'User',
            age: formData.age ? parseInt(formData.age) : undefined,
            skinType: formData.skinType,
            hairType: formData.hairType,
            concerns: formData.concerns || [],
            budget: formData.budget || 'medium',
            fragranceFree: formData.fragranceFree === 'yes' || formData.fragranceFree === true,
            location: formData.location || 'US',
        };
        return profile;
    }
}
exports.IntakeAgent = IntakeAgent;
