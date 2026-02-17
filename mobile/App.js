import { StyleSheet, Text, View, ScrollView, TextInput, TouchableOpacity, ActivityIndicator, SafeAreaView, Switch } from 'react-native';
import { useState } from 'react';

const API_BASE_URL = 'https://glowup-15ce3345c8f8.herokuapp.com';
const API_URL = `${API_BASE_URL}/api/analyze`;

export default function App() {
  const [step, setStep] = useState('intake'); // intake, analyzing, results
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);

  const [formData, setFormData] = useState({
    name: '',
    skinType: 'normal',
    hairType: 'straight',
    concerns: [],
    fragranceFree: false,
  });

  const concernsList = ['acne', 'aging', 'dryness', 'oiliness', 'pigmentation', 'sensitivity', 'frizz', 'damage', 'scalp_itch'];

  const toggleConcern = (concern) => {
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

  const handleSubmit = async () => {
    setLoading(true);
    setStep('analyzing');

    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(formData),
      });
      const data = await response.json();
      setResult(data);
      setStep('results');
    } catch (error) {
      console.error(error);
      alert('Error connecting to agents');
      setStep('intake');
    } finally {
      setLoading(false);
    }
  };

  if (step === 'intake') {
    return (
      <SafeAreaView style={styles.container}>
        <ScrollView contentContainerStyle={styles.scrollContent}>
          <Text style={styles.title}>✨ Personal Beauty Concierge</Text>
          <Text style={styles.subtitle}>Tell us about yourself</Text>

          <View style={styles.inputGroup}>
            <Text style={styles.label}>Name</Text>
            <TextInput
              style={styles.input}
              value={formData.name}
              onChangeText={(text) => setFormData({...formData, name: text})}
              placeholder="Your name"
            />
          </View>

          <View style={styles.inputGroup}>
            <Text style={styles.label}>Skin Type</Text>
            <View style={styles.chipContainer}>
              {['normal', 'oily', 'dry', 'combination', 'sensitive'].map(type => (
                <TouchableOpacity
                  key={type}
                  style={[styles.chip, formData.skinType === type && styles.chipSelected]}
                  onPress={() => setFormData({...formData, skinType: type})}
                >
                  <Text style={[styles.chipText, formData.skinType === type && styles.chipTextSelected]}>
                    {type.charAt(0).toUpperCase() + type.slice(1)}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>

          <View style={styles.inputGroup}>
            <Text style={styles.label}>Concerns</Text>
            <View style={styles.chipContainer}>
              {concernsList.map(concern => (
                <TouchableOpacity
                  key={concern}
                  style={[styles.chip, formData.concerns.includes(concern) && styles.chipSelected]}
                  onPress={() => toggleConcern(concern)}
                >
                  <Text style={[styles.chipText, formData.concerns.includes(concern) && styles.chipTextSelected]}>
                    {concern.replace('_', ' ')}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>

          <View style={styles.switchRow}>
            <Text style={styles.label}>Fragrance Free?</Text>
            <Switch
              value={formData.fragranceFree}
              onValueChange={(val) => setFormData({...formData, fragranceFree: val})}
            />
          </View>

          <TouchableOpacity style={styles.button} onPress={handleSubmit}>
            <Text style={styles.buttonText}>Generate Routine</Text>
          </TouchableOpacity>
        </ScrollView>
      </SafeAreaView>
    );
  }

  if (step === 'analyzing') {
    return (
      <View style={styles.centerContainer}>
        <ActivityIndicator size="large" color="#4F46E5" />
        <Text style={styles.loadingText}>Agents are analyzing your profile...</Text>
        <Text style={styles.loadingSubText}>Checking 300+ products...</Text>
      </View>
    );
  }

  if (step === 'results' && result) {
    const { routine, cart } = result;
    return (
      <SafeAreaView style={styles.container}>
        <ScrollView contentContainerStyle={styles.scrollContent}>
          <Text style={styles.title}>Your Routine</Text>
          <Text style={styles.explanation}>{routine.explanation}</Text>

          <Text style={styles.sectionHeader}>☀️ Morning</Text>
          {routine.skincareAM.map((step, idx) => (
            <View key={idx} style={styles.card}>
              <Text style={styles.stepName}>{step.stepName}</Text>
              <Text style={styles.productName}>{step.product?.name}</Text>
              <Text style={styles.brand}>{step.product?.brand}</Text>
              <Text style={styles.instruction}>{step.instruction}</Text>
            </View>
          ))}

          <Text style={styles.sectionHeader}>🌙 Evening</Text>
          {routine.skincarePM.map((step, idx) => (
            <View key={idx} style={styles.card}>
              <Text style={styles.stepName}>{step.stepName}</Text>
              <Text style={styles.productName}>{step.product?.name}</Text>
              <Text style={styles.brand}>{step.product?.brand}</Text>
              <Text style={styles.instruction}>{step.instruction}</Text>
            </View>
          ))}

          <View style={styles.cartSection}>
            <Text style={styles.sectionHeader}>Shopping Cart (${cart.totalPrice.toFixed(2)})</Text>
            {cart.items.map((item, idx) => (
              <View key={idx} style={styles.cartItem}>
                 <Text style={styles.cartItemName}>{item.product.name}</Text>
                 <Text style={styles.cartItemPrice}>${item.product.price}</Text>
              </View>
            ))}
            <TouchableOpacity style={styles.checkoutButton}>
              <Text style={styles.buttonText}>Checkout All</Text>
            </TouchableOpacity>
          </View>

          <TouchableOpacity style={styles.secondaryButton} onPress={() => setStep('intake')}>
            <Text style={styles.secondaryButtonText}>Start Over</Text>
          </TouchableOpacity>
        </ScrollView>
      </SafeAreaView>
    );
  }

  return null;
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F9FAFB',
  },
  scrollContent: {
    padding: 20,
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#1F2937',
    marginBottom: 8,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 16,
    color: '#6B7280',
    marginBottom: 24,
    textAlign: 'center',
  },
  inputGroup: {
    marginBottom: 20,
  },
  label: {
    fontSize: 16,
    fontWeight: '600',
    color: '#374151',
    marginBottom: 8,
  },
  input: {
    backgroundColor: 'white',
    borderWidth: 1,
    borderColor: '#D1D5DB',
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
  },
  chipContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  chip: {
    backgroundColor: '#E5E7EB',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
  },
  chipSelected: {
    backgroundColor: '#4F46E5',
  },
  chipText: {
    color: '#374151',
  },
  chipTextSelected: {
    color: 'white',
    fontWeight: '600',
  },
  switchRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 24,
  },
  button: {
    backgroundColor: '#4F46E5',
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: 'bold',
  },
  loadingText: {
    marginTop: 16,
    fontSize: 18,
    fontWeight: '600',
    color: '#374151',
  },
  loadingSubText: {
    marginTop: 8,
    color: '#6B7280',
  },
  sectionHeader: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#4F46E5',
    marginTop: 24,
    marginBottom: 12,
  },
  explanation: {
    fontSize: 16,
    color: '#4B5563',
    fontStyle: 'italic',
    marginBottom: 16,
    textAlign: 'center',
  },
  card: {
    backgroundColor: 'white',
    padding: 16,
    borderRadius: 12,
    marginBottom: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  stepName: {
    fontSize: 12,
    fontWeight: 'bold',
    color: '#6B7280',
    textTransform: 'uppercase',
  },
  productName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1F2937',
    marginTop: 4,
  },
  brand: {
    fontSize: 14,
    color: '#6B7280',
  },
  instruction: {
    fontSize: 14,
    color: '#374151',
    marginTop: 8,
    fontStyle: 'italic',
  },
  cartSection: {
    backgroundColor: '#F3F4F6',
    padding: 16,
    borderRadius: 12,
    marginTop: 24,
  },
  cartItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  cartItemName: {
    fontSize: 14,
    color: '#1F2937',
    flex: 1,
  },
  cartItemPrice: {
    fontSize: 14,
    fontWeight: '600',
    color: '#1F2937',
  },
  checkoutButton: {
    backgroundColor: '#111827',
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 16,
  },
  secondaryButton: {
    marginTop: 24,
    padding: 16,
    alignItems: 'center',
  },
  secondaryButtonText: {
    color: '#4F46E5',
    fontWeight: '600',
  },
});










