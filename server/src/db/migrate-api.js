// Run migrations via Supabase REST API (bypasses circuit breaker)
const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const supabaseUrl = 'https://ukhxwxmqjltfjugizbku.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVraHh3eG1xamx0Zmp1Z2l6Ymt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1NDA2NTUsImV4cCI6MjA4NTExNjY1NX0.x8sfd80Hmb6_wLtBG0Up9OqQZ49wjrhTE_wfdkVnPk4';

const supabase = createClient(supabaseUrl, supabaseKey);

async function checkConnection() {
  console.log('🔌 Testing Supabase connection...');
  
  // Test connection by querying tables
  const { data, error } = await supabase
    .from('products')
    .select('id', { count: 'exact', head: true });
  
  if (error && !error.message.includes('does not exist')) {
    console.error('❌ Connection error:', error.message);
    return false;
  }
  
  console.log('✅ Connected to Supabase!\n');
  return true;
}

async function listTables() {
  // Try to query each known table
  const tables = ['users', 'profiles', 'products', 'routines', 'skin_profiles', 'photo_check_ins', '_migrations'];
  const existing = [];
  
  for (const table of tables) {
    const { error } = await supabase
      .from(table)
      .select('*', { count: 'exact', head: true });
    
    if (!error || !error.message.includes('does not exist')) {
      existing.push(table);
    }
  }
  
  console.log('📋 Existing tables:', existing.join(', '));
  return existing;
}

async function getProductCount() {
  const { count, error } = await supabase
    .from('products')
    .select('*', { count: 'exact', head: true });
  
  if (error) {
    console.log('❌ Products table error:', error.message);
    return 0;
  }
  
  console.log(`📦 Products in database: ${count}`);
  return count;
}

async function getSkinProfileCount() {
  const { count, error } = await supabase
    .from('skin_profiles')
    .select('*', { count: 'exact', head: true });
  
  if (error) {
    console.log('⚠️ skin_profiles table:', error.message);
    return 0;
  }
  
  console.log(`👤 Skin profiles: ${count}`);
  return count;
}

async function main() {
  const connected = await checkConnection();
  if (!connected) {
    process.exit(1);
  }
  
  await listTables();
  await getProductCount();
  await getSkinProfileCount();
  
  console.log('\n✅ Database status check complete.');
  console.log('\nNote: Schema migrations should be run via Supabase Dashboard SQL Editor');
  console.log('  or use direct PostgreSQL when circuit breaker resets.');
}

main();





