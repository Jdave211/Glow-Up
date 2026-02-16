'use client';

import React, { useState } from 'react';
import { IntakeAgent } from '@/agents/intake';
import { RecommendationAgent } from '@/agents/recommendation';
import { ShoppingAgent } from '@/agents/shopping';
import { UserProfile, FullRoutine, ShoppingCart, Concern, SkinType, HairType } from '@/types';

// Instantiate agents
const intakeAgent = new IntakeAgent();
const recommendationAgent = new RecommendationAgent();
const shoppingAgent = new ShoppingAgent();

export default function LooksMaxxingApp() {
  const [step, setStep] = useState<'intake' | 'analyzing' | 'results' | 'cart'>('intake');
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [routine, setRoutine] = useState<FullRoutine | null>(null);
  const [cart, setCart] = useState<ShoppingCart | null>(null);

  // Form State
  const [formData, setFormData] = useState({
    name: '',
    age: '',
    skinType: 'normal' as SkinType,
    hairType: 'straight' as HairType,
    concerns: [] as Concern[],
    budget: 'medium',
    fragranceFree: false,
  });

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const { name, value, type } = e.target;
    if (type === 'checkbox') {
       const checked = (e.target as HTMLInputElement).checked;
       setFormData(prev => ({ ...prev, [name]: checked }));
    } else {
      setFormData(prev => ({ ...prev, [name]: value }));
    }
  };

  const toggleConcern = (concern: Concern) => {
    setFormData(prev => {
      const exists = prev.concerns.includes(concern);
      return {
        ...prev,
        concerns: exists 
          ? prev.concerns.filter(c => c !== concern)
          : [...prev.concerns, concern]
      };
    });
  };

  const handleSubmitIntake = async () => {
    setStep('analyzing');
    
    // Simulate processing delay
    setTimeout(async () => {
      const userProfile = await intakeAgent.analyze(formData);
      setProfile(userProfile);
      
      const generatedRoutine = await recommendationAgent.generateRoutine(userProfile);
      setRoutine(generatedRoutine);
      
      const generatedCart = await shoppingAgent.buildCart(generatedRoutine);
      setCart(generatedCart);
      
      setStep('results');
    }, 1500);
  };

  if (step === 'intake') {
    return (
      <div className="max-w-2xl mx-auto p-6 bg-white rounded-xl shadow-lg">
        <h1 className="text-3xl font-bold mb-6 text-center text-slate-800">✨ Personal Beauty Concierge</h1>
        <p className="mb-6 text-slate-600 text-center">Tell us about yourself to get a personalized routine.</p>
        
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-slate-700">Name</label>
            <input type="text" name="name" value={formData.name} onChange={handleInputChange} className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 border p-2 text-slate-900" />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-slate-700">Skin Type</label>
              <select name="skinType" value={formData.skinType} onChange={handleInputChange} className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 border p-2 text-slate-900">
                <option value="normal">Normal</option>
                <option value="oily">Oily</option>
                <option value="dry">Dry</option>
                <option value="combination">Combination</option>
                <option value="sensitive">Sensitive</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700">Hair Type</label>
              <select name="hairType" value={formData.hairType} onChange={handleInputChange} className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 border p-2 text-slate-900">
                <option value="straight">Straight</option>
                <option value="wavy">Wavy</option>
                <option value="curly">Curly</option>
                <option value="coily">Coily</option>
              </select>
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-2">Concerns (Select all that apply)</label>
            <div className="flex flex-wrap gap-2">
              {(['acne', 'aging', 'dryness', 'oiliness', 'pigmentation', 'sensitivity', 'frizz', 'damage', 'scalp_itch'] as Concern[]).map(concern => (
                <button
                  key={concern}
                  onClick={() => toggleConcern(concern)}
                  className={`px-3 py-1 rounded-full text-sm font-medium transition-colors ${
                    formData.concerns.includes(concern)
                      ? 'bg-indigo-600 text-white'
                      : 'bg-slate-100 text-slate-700 hover:bg-slate-200'
                  }`}
                >
                  {concern.charAt(0).toUpperCase() + concern.slice(1).replace('_', ' ')}
                </button>
              ))}
            </div>
          </div>

          <div className="flex items-center">
            <input
              type="checkbox"
              name="fragranceFree"
              checked={formData.fragranceFree}
              onChange={handleInputChange}
              className="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
            />
            <label className="ml-2 block text-sm text-slate-900">Prefer fragrance-free products?</label>
          </div>

          <div className="pt-4">
             {/* Placeholder for Photo Upload */}
            <div className="border-2 border-dashed border-slate-300 rounded-lg p-6 text-center text-slate-500">
              <p>📸 Upload Photos (Front & Side)</p>
              <p className="text-xs mt-1">(AI Analysis coming soon)</p>
            </div>
          </div>

          <button
            onClick={handleSubmitIntake}
            className="w-full flex justify-center py-3 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 mt-6"
          >
            Generate My Routine
          </button>
        </div>
      </div>
    );
  }

  if (step === 'analyzing') {
    return (
      <div className="flex flex-col items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600 mb-4"></div>
        <h2 className="text-xl font-semibold text-slate-800">Agents are working...</h2>
        <ul className="text-slate-500 mt-2 space-y-1 text-sm text-center">
          <li>Analyzing profile...</li>
          <li>Matching ingredients...</li>
          <li>Checking prices...</li>
        </ul>
      </div>
    );
  }

  if (step === 'results' && routine) {
    return (
      <div className="max-w-4xl mx-auto p-4 space-y-6">
        <div className="bg-white rounded-xl shadow-lg p-6">
          <h2 className="text-2xl font-bold text-slate-800 mb-2">Your Personalized Routine</h2>
          <p className="text-slate-600 mb-6">{routine.explanation}</p>

          <div className="grid md:grid-cols-3 gap-6">
            <div>
              <h3 className="text-lg font-semibold text-indigo-600 mb-3">☀️ Morning (AM)</h3>
              <div className="space-y-4">
                {routine.skincareAM.map((step, idx) => (
                  <div key={idx} className="bg-slate-50 p-3 rounded-lg">
                    <div className="text-sm font-bold text-slate-700 uppercase tracking-wide">{step.stepName}</div>
                    <div className="font-medium text-slate-900 mt-1">{step.product?.name}</div>
                    <div className="text-xs text-slate-500">{step.product?.brand}</div>
                    <p className="text-sm text-slate-600 mt-2 italic">"{step.instruction}"</p>
                  </div>
                ))}
              </div>
            </div>

            <div>
              <h3 className="text-lg font-semibold text-indigo-600 mb-3">🌙 Evening (PM)</h3>
              <div className="space-y-4">
                {routine.skincarePM.map((step, idx) => (
                  <div key={idx} className="bg-slate-50 p-3 rounded-lg">
                    <div className="text-sm font-bold text-slate-700 uppercase tracking-wide">{step.stepName}</div>
                    <div className="font-medium text-slate-900 mt-1">{step.product?.name}</div>
                    <div className="text-xs text-slate-500">{step.product?.brand}</div>
                    <p className="text-sm text-slate-600 mt-2 italic">"{step.instruction}"</p>
                  </div>
                ))}
              </div>
            </div>

            <div>
              <h3 className="text-lg font-semibold text-indigo-600 mb-3">🧖‍♀️ Hair</h3>
              <div className="space-y-4">
                {routine.haircare.map((step, idx) => (
                   <div key={idx} className="bg-slate-50 p-3 rounded-lg">
                    <div className="text-sm font-bold text-slate-700 uppercase tracking-wide">{step.stepName}</div>
                    <div className="font-medium text-slate-900 mt-1">{step.product?.name}</div>
                    <div className="text-xs text-slate-500">{step.product?.brand}</div>
                    <p className="text-sm text-slate-600 mt-2 italic">"{step.instruction}"</p>
                  </div>
                ))}
                 {routine.haircare.length === 0 && <p className="text-slate-500">No specific hair products added yet.</p>}
              </div>
            </div>
          </div>
        </div>
        
        <div className="flex justify-center">
            <button
            onClick={() => setStep('cart')}
            className="py-3 px-8 bg-indigo-600 text-white rounded-full font-bold shadow-lg hover:bg-indigo-700 transition-transform transform hover:-translate-y-1"
            >
            Review Shopping Cart ({cart?.items.length} items)
            </button>
        </div>
      </div>
    );
  }

  if (step === 'cart' && cart) {
    return (
       <div className="max-w-2xl mx-auto p-6 bg-white rounded-xl shadow-lg">
         <div className="flex justify-between items-center mb-6">
            <h2 className="text-2xl font-bold text-slate-800">Shopping Cart</h2>
            <button onClick={() => setStep('results')} className="text-indigo-600 hover:text-indigo-800">Back to Routine</button>
         </div>
        
        <div className="space-y-4 divide-y divide-slate-100">
          {cart.items.map((item, idx) => (
            <div key={idx} className="flex justify-between items-center py-2">
              <div>
                <p className="font-semibold text-slate-900">{item.product.name}</p>
                <p className="text-sm text-slate-500">{item.product.brand} • {item.product.retailer}</p>
              </div>
              <div className="font-mono text-slate-700">
                ${item.product.price.toFixed(2)}
              </div>
            </div>
          ))}
        </div>

        <div className="mt-6 pt-4 border-t border-slate-200">
          <div className="flex justify-between items-center text-xl font-bold text-slate-900">
            <span>Total</span>
            <span>${cart.totalPrice.toFixed(2)}</span>
          </div>
        </div>

        <div className="mt-8 space-y-3">
          {cart.retailerLinks.map((link, idx) => (
            <a
              key={idx}
              href={link.cartUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="block w-full text-center py-3 bg-black text-white rounded-lg hover:bg-slate-800 transition-colors"
            >
              Checkout at {link.retailer}
            </a>
          ))}
        </div>
       </div>
    );
  }

  return null;
}

