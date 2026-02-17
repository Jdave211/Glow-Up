import { StyleSheet, Text, View, ScrollView, TextInput, TouchableOpacity, ActivityIndicator, SafeAreaView, Switch, Animated, Easing, Image, Dimensions } from 'react-native';
import { useState, useEffect, useRef } from 'react';
import { LinearGradient } from 'expo-linear-gradient';

const { width, height } = Dimensions.get('window');
<<<<<<< HEAD
const API_BASE_URL = 'https://glowup-15ce3345c8f8.herokuapp.com';
=======
const API_BASE_URL = process.env.EXPO_PUBLIC_API_BASE_URL || 'http://localhost:4000';
>>>>>>> 39757e8ceedb4e68ba6ad98e49c457179036211c
const API_URL = `${API_BASE_URL}/api/analyze`;

// Agent avatars with emojis
const AGENTS = [
  { emoji: '🧴', name: 'Skin', color: '#FF6B9D' },
  { emoji: '💇', name: 'Hair', color: '#FF8FB1' },
  { emoji: '🔍', name: 'Match', color: '#FFB4C8' },
  { emoji: '💰', name: 'Budget', color: '#FFC8DD' },
];

// Floating element component
function FloatingElement({ children, style, delay = 0 }) {
  const floatAnim = useRef(new Animated.Value(0)).current;
  
  useEffect(() => {
    Animated.loop(
      Animated.sequence([
        Animated.timing(floatAnim, { toValue: 1, duration: 2000, delay, useNativeDriver: true }),
        Animated.timing(floatAnim, { toValue: 0, duration: 2000, useNativeDriver: true }),
      ])
    ).start();
  }, []);

  const translateY = floatAnim.interpolate({
    inputRange: [0, 1],
    outputRange: [0, -10],
  });

  return (
    <Animated.View style={[style, { transform: [{ translateY }] }]}>
      {children}
    </Animated.View>
  );
}

// Agent thinking card
function AgentThinkingCard({ agent, isActive, index }) {
  const scaleAnim = useRef(new Animated.Value(0)).current;
  const [showThoughts, setShowThoughts] = useState(false);

  useEffect(() => {
    if (isActive) {
      Animated.spring(scaleAnim, {
        toValue: 1,
        tension: 50,
        friction: 7,
        useNativeDriver: true,
      }).start();
      setTimeout(() => setShowThoughts(true), 400);
    }
  }, [isActive]);

  if (!isActive) return null;

  return (
    <Animated.View style={[styles.agentThinkCard, { transform: [{ scale: scaleAnim }] }]}>
      <View style={styles.agentThinkHeader}>
        <View style={[styles.agentAvatar, { backgroundColor: AGENTS[index]?.color || '#FF6B9D' }]}>
          <Text style={styles.agentAvatarEmoji}>{agent.emoji}</Text>
        </View>
        <View style={styles.agentThinkInfo}>
          <Text style={styles.agentThinkName}>{agent.agentName}</Text>
          <View style={styles.confidenceBar}>
            <View style={[styles.confidenceFill, { width: `${agent.confidence * 100}%` }]} />
          </View>
        </View>
      </View>
      
      {showThoughts && (
        <View style={styles.thoughtsContainer}>
          {agent.thinking.slice(0, 3).map((thought, idx) => (
            <View key={idx} style={[
              styles.thoughtChip,
              thought.conclusion && styles.conclusionChip
            ]}>
              <Text style={[
                styles.thoughtChipText,
                thought.conclusion && styles.conclusionChipText
              ]} numberOfLines={2}>
                {thought.conclusion || thought.thought}
              </Text>
            </View>
          ))}
        </View>
      )}
    </Animated.View>
  );
}

export default function App() {
  const [step, setStep] = useState('welcome');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [activeAgentIndex, setActiveAgentIndex] = useState(0);

  const [formData, setFormData] = useState({
    name: '',
    skinType: 'normal',
    hairType: 'straight',
    concerns: [],
    budget: 'medium',
    fragranceFree: false,
  });

  const concernsList = ['acne', 'aging', 'dryness', 'oiliness', 'pigmentation', 'sensitivity', 'frizz', 'damage'];

  const toggleConcern = (concern) => {
    setFormData(prev => ({
      ...prev,
      concerns: prev.concerns.includes(concern)
        ? prev.concerns.filter(c => c !== concern)
        : [...prev.concerns, concern]
    }));
  };

  const handleSubmit = async () => {
    setLoading(true);
    setStep('analyzing');
    setActiveAgentIndex(0);

    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData),
      });
      const data = await response.json();
      setResult(data);
      
      data.agents.forEach((_, idx) => {
        setTimeout(() => setActiveAgentIndex(idx + 1), idx * 1500 + 500);
      });

      setTimeout(() => setStep('results'), data.agents.length * 1500 + 2000);
    } catch (error) {
      console.error(error);
      alert('Error connecting to agents');
      setStep('intake');
    } finally {
      setLoading(false);
    }
  };

  // ═══════════════════════════════════════════════════════════════
  // WELCOME SCREEN
  // ═══════════════════════════════════════════════════════════════
  if (step === 'welcome') {
    return (
      <View style={styles.container}>
        <LinearGradient
          colors={['#FFF0F5', '#FFE4EC', '#FFF5F8']}
          style={styles.gradient}
        >
          <SafeAreaView style={styles.safeArea}>
            <View style={styles.welcomeContent}>
              {/* Floating decorations */}
              <FloatingElement style={styles.floatTopLeft} delay={0}>
                <Text style={styles.floatEmoji}>✨</Text>
              </FloatingElement>
              <FloatingElement style={styles.floatTopRight} delay={500}>
                <Text style={styles.floatEmoji}>🌸</Text>
              </FloatingElement>
              <FloatingElement style={styles.floatBottomLeft} delay={1000}>
                <Text style={styles.floatEmoji}>💫</Text>
              </FloatingElement>

              {/* Logo */}
              <View style={styles.logoContainer}>
                <View style={styles.logoBg}>
                  <Text style={styles.logoEmoji}>💅</Text>
                </View>
                <Text style={styles.logoText}>GlowUp</Text>
              </View>

              {/* Hero card with image placeholder */}
              <View style={styles.heroCard}>
                <View style={styles.heroImagePlaceholder}>
                  <Text style={styles.heroImageEmoji}>👩‍🦰👩🏽👩🏻‍🦱</Text>
                </View>
              </View>

              {/* Agent preview */}
              <View style={styles.agentRow}>
                {AGENTS.map((agent, idx) => (
                  <View key={idx} style={[styles.agentBubble, { backgroundColor: agent.color }]}>
                    <Text style={styles.agentBubbleEmoji}>{agent.emoji}</Text>
                  </View>
                ))}
              </View>

              {/* Welcome text */}
              <Text style={styles.welcomeTitle}>welcome to glowup</Text>
              <Text style={styles.welcomeSubtitle}>your ai beauty bestie 💕</Text>

              {/* CTA */}
              <TouchableOpacity 
                style={styles.ctaButton}
                onPress={() => setStep('intake')}
              >
                <LinearGradient
                  colors={['#FF6B9D', '#FF8FB1']}
                  start={{ x: 0, y: 0 }}
                  end={{ x: 1, y: 0 }}
                  style={styles.ctaGradient}
                >
                  <Text style={styles.ctaText}>Get Started</Text>
                  <Text style={styles.ctaEmoji}>🎉</Text>
                </LinearGradient>
              </TouchableOpacity>
            </View>
          </SafeAreaView>
        </LinearGradient>
      </View>
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // INTAKE SCREEN
  // ═══════════════════════════════════════════════════════════════
  if (step === 'intake') {
    return (
      <View style={styles.container}>
        <LinearGradient
          colors={['#FFF0F5', '#FFFFFF']}
          style={styles.gradient}
        >
          <SafeAreaView style={styles.safeArea}>
            <ScrollView 
              contentContainerStyle={styles.scrollContent}
              showsVerticalScrollIndicator={false}
            >
              {/* Header */}
              <View style={styles.intakeHeader}>
                <TouchableOpacity onPress={() => setStep('welcome')}>
                  <Text style={styles.backButton}>←</Text>
                </TouchableOpacity>
                <Text style={styles.intakeTitle}>tell us about you ✨</Text>
                <View style={{ width: 24 }} />
              </View>

              {/* Name input */}
              <View style={styles.inputCard}>
                <Text style={styles.inputLabel}>what's your name?</Text>
                <TextInput
                  style={styles.textInput}
                  value={formData.name}
                  onChangeText={(text) => setFormData({...formData, name: text})}
                  placeholder="enter your name"
                  placeholderTextColor="#FFADC6"
                />
              </View>

              {/* Skin type */}
              <View style={styles.inputCard}>
                <Text style={styles.inputLabel}>skin type 🧴</Text>
                <View style={styles.optionRow}>
                  {['normal', 'oily', 'dry', 'combo', 'sensitive'].map(type => (
                    <TouchableOpacity
                      key={type}
                      style={[
                        styles.optionChip,
                        formData.skinType === type && styles.optionChipSelected
                      ]}
                      onPress={() => setFormData({...formData, skinType: type})}
                    >
                      <Text style={[
                        styles.optionChipText,
                        formData.skinType === type && styles.optionChipTextSelected
                      ]}>{type}</Text>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>

              {/* Hair type */}
              <View style={styles.inputCard}>
                <Text style={styles.inputLabel}>hair type 💇</Text>
                <View style={styles.optionRow}>
                  {['straight', 'wavy', 'curly', 'coily'].map(type => (
                    <TouchableOpacity
                      key={type}
                      style={[
                        styles.optionChip,
                        formData.hairType === type && styles.optionChipSelected
                      ]}
                      onPress={() => setFormData({...formData, hairType: type})}
                    >
                      <Text style={[
                        styles.optionChipText,
                        formData.hairType === type && styles.optionChipTextSelected
                      ]}>{type}</Text>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>

              {/* Concerns */}
              <View style={styles.inputCard}>
                <Text style={styles.inputLabel}>concerns 💭</Text>
                <View style={styles.optionRow}>
                  {concernsList.map(concern => (
                    <TouchableOpacity
                      key={concern}
                      style={[
                        styles.optionChip,
                        formData.concerns.includes(concern) && styles.optionChipSelectedAlt
                      ]}
                      onPress={() => toggleConcern(concern)}
                    >
                      <Text style={[
                        styles.optionChipText,
                        formData.concerns.includes(concern) && styles.optionChipTextSelected
                      ]}>{concern}</Text>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>

              {/* Budget */}
              <View style={styles.inputCard}>
                <Text style={styles.inputLabel}>budget 💸</Text>
                <View style={styles.budgetRow}>
                  {[
                    { key: 'low', label: 'budget babe', emoji: '💅' },
                    { key: 'medium', label: 'treat yourself', emoji: '✨' },
                    { key: 'high', label: 'luxury queen', emoji: '👑' },
                  ].map(b => (
                    <TouchableOpacity
                      key={b.key}
                      style={[
                        styles.budgetCard,
                        formData.budget === b.key && styles.budgetCardSelected
                      ]}
                      onPress={() => setFormData({...formData, budget: b.key})}
                    >
                      <Text style={styles.budgetEmoji}>{b.emoji}</Text>
                      <Text style={[
                        styles.budgetLabel,
                        formData.budget === b.key && styles.budgetLabelSelected
                      ]}>{b.label}</Text>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>

              {/* Fragrance toggle */}
              <View style={styles.toggleCard}>
                <Text style={styles.toggleLabel}>fragrance-free only</Text>
                <Switch
                  value={formData.fragranceFree}
                  onValueChange={(val) => setFormData({...formData, fragranceFree: val})}
                  trackColor={{ false: '#FFE4EC', true: '#FFB4C8' }}
                  thumbColor={formData.fragranceFree ? '#FF6B9D' : '#fff'}
                />
              </View>

              {/* Submit */}
              <TouchableOpacity style={styles.analyzeButton} onPress={handleSubmit}>
                <LinearGradient
                  colors={['#FF6B9D', '#FF8FB1']}
                  start={{ x: 0, y: 0 }}
                  end={{ x: 1, y: 0 }}
                  style={styles.analyzeGradient}
                >
                  <Text style={styles.analyzeText}>analyze with 4 agents</Text>
                  <Text style={styles.analyzeEmoji}>🔮</Text>
                </LinearGradient>
              </TouchableOpacity>
            </ScrollView>
          </SafeAreaView>
        </LinearGradient>
      </View>
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ANALYZING SCREEN
  // ═══════════════════════════════════════════════════════════════
  if (step === 'analyzing' && result) {
    return (
      <View style={styles.container}>
        <LinearGradient
          colors={['#2D1F3D', '#1A1225', '#0F0A15']}
          style={styles.gradient}
        >
          <SafeAreaView style={styles.safeArea}>
            <ScrollView contentContainerStyle={styles.scrollContent}>
              <View style={styles.analyzeHeader}>
                <Text style={styles.analyzeTitle}>✨ agents thinking ✨</Text>
                <Text style={styles.analyzeSubtitle}>deep analysis in progress...</Text>
              </View>

              {/* Agent progress */}
              <View style={styles.agentProgress}>
                {AGENTS.map((agent, idx) => (
                  <View 
                    key={idx} 
                    style={[
                      styles.agentProgressBubble,
                      { backgroundColor: idx < activeAgentIndex ? agent.color : '#3D2D4D' }
                    ]}
                  >
                    <Text style={styles.agentProgressEmoji}>{agent.emoji}</Text>
                    {idx < activeAgentIndex && (
                      <View style={styles.checkMark}>
                        <Text style={styles.checkMarkText}>✓</Text>
                      </View>
                    )}
                  </View>
                ))}
              </View>

              {/* Agent cards */}
              {result.agents.map((agent, idx) => (
                <AgentThinkingCard
                  key={idx}
                  agent={agent}
                  isActive={idx < activeAgentIndex}
                  index={idx}
                />
              ))}

              {activeAgentIndex <= result.agents.length && (
                <View style={styles.loadingContainer}>
                  <ActivityIndicator size="large" color="#FF6B9D" />
                </View>
              )}
            </ScrollView>
          </SafeAreaView>
        </LinearGradient>
      </View>
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // RESULTS SCREEN
  // ═══════════════════════════════════════════════════════════════
  if (step === 'results' && result) {
    const products = result.agents[2]?.recommendations || [];
    const budget = result.agents[3]?.recommendations || {};

    return (
      <View style={styles.container}>
        <LinearGradient
          colors={['#FFF0F5', '#FFFFFF']}
          style={styles.gradient}
        >
          <SafeAreaView style={styles.safeArea}>
            <ScrollView contentContainerStyle={styles.scrollContent}>
              {/* Results header */}
              <View style={styles.resultsHeader}>
                <Text style={styles.resultsTitle}>your glow up ✨</Text>
                <View style={styles.confidenceCircle}>
                  <Text style={styles.confidencePercent}>{(result.summary.overallConfidence * 100).toFixed(0)}%</Text>
                  <Text style={styles.confidenceLabel}>match</Text>
                </View>
              </View>

              {/* Quick stats */}
              <View style={styles.statsRow}>
                <View style={styles.statCard}>
                  <Text style={styles.statValue}>{result.summary.totalProducts}</Text>
                  <Text style={styles.statLabel}>products</Text>
                </View>
                <View style={styles.statCard}>
                  <Text style={styles.statValue}>${result.summary.totalCost?.toFixed(0)}</Text>
                  <Text style={styles.statLabel}>total</Text>
                </View>
                <View style={styles.statCard}>
                  <Text style={styles.statValue}>${budget.monthlyEstimate?.toFixed(0)}</Text>
                  <Text style={styles.statLabel}>/month</Text>
                </View>
              </View>

              {/* Products */}
              <Text style={styles.sectionTitle}>recommended for you 💕</Text>
              {products.map((product, idx) => (
                <View key={idx} style={styles.productCard}>
                  <View style={styles.productBadge}>
                    <Text style={styles.productBadgeText}>{(product.match * 100).toFixed(0)}%</Text>
                  </View>
                  <View style={styles.productInfo}>
                    <Text style={styles.productName}>{product.name}</Text>
                    <View style={styles.productMeta}>
                      <Text style={styles.productRating}>⭐ {product.rating}</Text>
                      <Text style={styles.productCategory}>{product.category}</Text>
                    </View>
                  </View>
                  <Text style={styles.productPrice}>${product.price}</Text>
                </View>
              ))}

              {/* Agent insights */}
              <Text style={styles.sectionTitle}>agent insights 🔮</Text>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.insightsScroll}>
                {result.agents.map((agent, idx) => (
                  <View key={idx} style={[styles.insightCard, { backgroundColor: AGENTS[idx]?.color || '#FF6B9D' }]}>
                    <Text style={styles.insightEmoji}>{agent.emoji}</Text>
                    <Text style={styles.insightName}>{agent.agentName.split(' ')[0]}</Text>
                    <Text style={styles.insightText} numberOfLines={3}>
                      {agent.thinking.find(t => t.conclusion)?.conclusion || 'Analysis complete'}
                    </Text>
                  </View>
                ))}
              </ScrollView>

              {/* Checkout */}
              <TouchableOpacity style={styles.checkoutButton}>
                <LinearGradient
                  colors={['#FF6B9D', '#FF8FB1']}
                  start={{ x: 0, y: 0 }}
                  end={{ x: 1, y: 0 }}
                  style={styles.checkoutGradient}
                >
                  <Text style={styles.checkoutText}>shop all • ${result.summary.totalCost?.toFixed(2)}</Text>
                </LinearGradient>
              </TouchableOpacity>

              <TouchableOpacity style={styles.restartButton} onPress={() => { setStep('welcome'); setResult(null); }}>
                <Text style={styles.restartText}>start over 💫</Text>
              </TouchableOpacity>
            </ScrollView>
          </SafeAreaView>
        </LinearGradient>
      </View>
    );
  }

  return null;
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  gradient: {
    flex: 1,
  },
  safeArea: {
    flex: 1,
  },
  scrollContent: {
    padding: 20,
    paddingBottom: 40,
  },

  // Welcome Screen
  welcomeContent: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 20,
  },
  floatTopLeft: { position: 'absolute', top: 60, left: 30 },
  floatTopRight: { position: 'absolute', top: 100, right: 40 },
  floatBottomLeft: { position: 'absolute', bottom: 200, left: 50 },
  floatEmoji: { fontSize: 32 },
  logoContainer: {
    alignItems: 'center',
    marginBottom: 24,
  },
  logoBg: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: '#FFE4EC',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 12,
  },
  logoEmoji: { fontSize: 40 },
  logoText: {
    fontSize: 24,
    fontWeight: '700',
    color: '#FF6B9D',
  },
  heroCard: {
    width: width - 80,
    height: 280,
    backgroundColor: '#FFFFFF',
    borderRadius: 24,
    padding: 8,
    shadowColor: '#FF6B9D',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.15,
    shadowRadius: 24,
    elevation: 8,
    marginBottom: 24,
  },
  heroImagePlaceholder: {
    flex: 1,
    backgroundColor: '#FFE4EC',
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
  },
  heroImageEmoji: { fontSize: 64 },
  agentRow: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 32,
  },
  agentBubble: {
    width: 52,
    height: 52,
    borderRadius: 26,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
  },
  agentBubbleEmoji: { fontSize: 24 },
  welcomeTitle: {
    fontSize: 28,
    fontWeight: '800',
    color: '#2D2D2D',
    marginBottom: 8,
  },
  welcomeSubtitle: {
    fontSize: 18,
    color: '#888',
    marginBottom: 40,
  },
  ctaButton: {
    width: '100%',
    borderRadius: 20,
    overflow: 'hidden',
  },
  ctaGradient: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 18,
    gap: 8,
  },
  ctaText: {
    fontSize: 18,
    fontWeight: '700',
    color: '#FFF',
  },
  ctaEmoji: { fontSize: 20 },

  // Intake Screen
  intakeHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 24,
  },
  backButton: {
    fontSize: 28,
    color: '#FF6B9D',
  },
  intakeTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: '#2D2D2D',
  },
  inputCard: {
    backgroundColor: '#FFF',
    borderRadius: 20,
    padding: 20,
    marginBottom: 16,
    shadowColor: '#FF6B9D',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.08,
    shadowRadius: 12,
  },
  inputLabel: {
    fontSize: 16,
    fontWeight: '600',
    color: '#2D2D2D',
    marginBottom: 12,
  },
  textInput: {
    backgroundColor: '#FFF5F8',
    borderRadius: 12,
    padding: 16,
    fontSize: 16,
    color: '#2D2D2D',
    borderWidth: 1,
    borderColor: '#FFE4EC',
  },
  optionRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  optionChip: {
    backgroundColor: '#FFF5F8',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: '#FFE4EC',
  },
  optionChipSelected: {
    backgroundColor: '#FF6B9D',
    borderColor: '#FF6B9D',
  },
  optionChipSelectedAlt: {
    backgroundColor: '#FF8FB1',
    borderColor: '#FF8FB1',
  },
  optionChipText: {
    fontSize: 14,
    color: '#888',
    fontWeight: '500',
  },
  optionChipTextSelected: {
    color: '#FFF',
  },
  budgetRow: {
    flexDirection: 'row',
    gap: 12,
  },
  budgetCard: {
    flex: 1,
    backgroundColor: '#FFF5F8',
    borderRadius: 16,
    padding: 16,
    alignItems: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  budgetCardSelected: {
    borderColor: '#FF6B9D',
    backgroundColor: '#FFE4EC',
  },
  budgetEmoji: { fontSize: 28, marginBottom: 8 },
  budgetLabel: {
    fontSize: 11,
    color: '#888',
    fontWeight: '600',
    textAlign: 'center',
  },
  budgetLabelSelected: { color: '#FF6B9D' },
  toggleCard: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: '#FFF',
    borderRadius: 20,
    padding: 20,
    marginBottom: 24,
  },
  toggleLabel: {
    fontSize: 16,
    color: '#2D2D2D',
    fontWeight: '500',
  },
  analyzeButton: {
    borderRadius: 20,
    overflow: 'hidden',
    marginTop: 8,
  },
  analyzeGradient: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 18,
    gap: 8,
  },
  analyzeText: {
    fontSize: 16,
    fontWeight: '700',
    color: '#FFF',
  },
  analyzeEmoji: { fontSize: 18 },

  // Analyzing Screen
  analyzeHeader: {
    alignItems: 'center',
    marginBottom: 32,
    paddingTop: 20,
  },
  analyzeTitle: {
    fontSize: 24,
    fontWeight: '800',
    color: '#FFF',
  },
  analyzeSubtitle: {
    fontSize: 16,
    color: '#FFB4C8',
    marginTop: 8,
  },
  agentProgress: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 16,
    marginBottom: 32,
  },
  agentProgressBubble: {
    width: 56,
    height: 56,
    borderRadius: 28,
    justifyContent: 'center',
    alignItems: 'center',
    position: 'relative',
  },
  agentProgressEmoji: { fontSize: 24 },
  checkMark: {
    position: 'absolute',
    bottom: -4,
    right: -4,
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: '#4ADE80',
    justifyContent: 'center',
    alignItems: 'center',
  },
  checkMarkText: { color: '#FFF', fontSize: 12, fontWeight: '700' },
  agentThinkCard: {
    backgroundColor: '#2D2040',
    borderRadius: 20,
    padding: 20,
    marginBottom: 16,
  },
  agentThinkHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
  },
  agentAvatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  agentAvatarEmoji: { fontSize: 24 },
  agentThinkInfo: { flex: 1 },
  agentThinkName: {
    fontSize: 16,
    fontWeight: '700',
    color: '#FFF',
    marginBottom: 8,
  },
  confidenceBar: {
    height: 6,
    backgroundColor: '#3D2D50',
    borderRadius: 3,
    overflow: 'hidden',
  },
  confidenceFill: {
    height: '100%',
    backgroundColor: '#FF6B9D',
    borderRadius: 3,
  },
  thoughtsContainer: { gap: 8 },
  thoughtChip: {
    backgroundColor: '#3D2D50',
    borderRadius: 12,
    padding: 12,
  },
  conclusionChip: {
    backgroundColor: '#4A2D60',
    borderLeftWidth: 3,
    borderLeftColor: '#FF6B9D',
  },
  thoughtChipText: {
    fontSize: 13,
    color: '#CCC',
    lineHeight: 18,
  },
  conclusionChipText: {
    color: '#FFF',
    fontWeight: '600',
  },
  loadingContainer: {
    alignItems: 'center',
    paddingVertical: 32,
  },

  // Results Screen
  resultsHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 24,
    paddingTop: 10,
  },
  resultsTitle: {
    fontSize: 28,
    fontWeight: '800',
    color: '#2D2D2D',
  },
  confidenceCircle: {
    width: 70,
    height: 70,
    borderRadius: 35,
    backgroundColor: '#FFE4EC',
    justifyContent: 'center',
    alignItems: 'center',
  },
  confidencePercent: {
    fontSize: 20,
    fontWeight: '800',
    color: '#FF6B9D',
  },
  confidenceLabel: {
    fontSize: 10,
    color: '#FF8FB1',
    fontWeight: '600',
  },
  statsRow: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 24,
  },
  statCard: {
    flex: 1,
    backgroundColor: '#FFF',
    borderRadius: 16,
    padding: 16,
    alignItems: 'center',
    shadowColor: '#FF6B9D',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 8,
  },
  statValue: {
    fontSize: 24,
    fontWeight: '800',
    color: '#FF6B9D',
  },
  statLabel: {
    fontSize: 12,
    color: '#888',
    marginTop: 4,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: '#2D2D2D',
    marginBottom: 16,
  },
  productCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#FFF',
    borderRadius: 16,
    padding: 16,
    marginBottom: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.04,
    shadowRadius: 8,
  },
  productBadge: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#FFE4EC',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  productBadgeText: {
    fontSize: 12,
    fontWeight: '700',
    color: '#FF6B9D',
  },
  productInfo: { flex: 1 },
  productName: {
    fontSize: 14,
    fontWeight: '600',
    color: '#2D2D2D',
    marginBottom: 4,
  },
  productMeta: {
    flexDirection: 'row',
    gap: 8,
  },
  productRating: {
    fontSize: 12,
    color: '#888',
  },
  productCategory: {
    fontSize: 12,
    color: '#FFB4C8',
    fontWeight: '500',
  },
  productPrice: {
    fontSize: 16,
    fontWeight: '700',
    color: '#FF6B9D',
  },
  insightsScroll: {
    marginBottom: 24,
    marginHorizontal: -20,
    paddingHorizontal: 20,
  },
  insightCard: {
    width: 140,
    borderRadius: 20,
    padding: 16,
    marginRight: 12,
    alignItems: 'center',
  },
  insightEmoji: { fontSize: 32, marginBottom: 8 },
  insightName: {
    fontSize: 14,
    fontWeight: '700',
    color: '#FFF',
    marginBottom: 8,
  },
  insightText: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.9)',
    textAlign: 'center',
    lineHeight: 16,
  },
  checkoutButton: {
    borderRadius: 20,
    overflow: 'hidden',
  },
  checkoutGradient: {
    paddingVertical: 18,
    alignItems: 'center',
  },
  checkoutText: {
    fontSize: 16,
    fontWeight: '700',
    color: '#FFF',
  },
  restartButton: {
    paddingVertical: 16,
    alignItems: 'center',
    marginTop: 8,
  },
  restartText: {
    fontSize: 14,
    color: '#FF6B9D',
    fontWeight: '600',
  },
});









<<<<<<< HEAD
=======


>>>>>>> 39757e8ceedb4e68ba6ad98e49c457179036211c
