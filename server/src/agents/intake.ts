import { UserProfile } from '../types';

export class IntakeAgent {
  async analyze(formData: any): Promise<UserProfile> {
    // In a real app, this would process images using Vision API
    // and merge findings with form data.
    // For now, we just validate and structure the form data.

    const profile: UserProfile = {
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

