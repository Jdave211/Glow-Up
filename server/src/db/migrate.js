const { Client } = require('pg');
const fs = require('fs');
const path = require('path');
const dns = require('dns');

// Force IPv4
dns.setDefaultResultOrder('ipv4first');

// Database connection
const DATABASE_URL = process.env.DATABASE_URL || 
  'postgresql://postgres.ukhxwxmqjltfjugizbku:hPbvmXh7zAyZKvJH@aws-1-us-east-2.pooler.supabase.com:6543/postgres';

const client = new Client({
  connectionString: DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

// Track applied migrations
const MIGRATIONS_TABLE = `
  CREATE TABLE IF NOT EXISTS _migrations (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    applied_at TIMESTAMPTZ DEFAULT NOW()
  );
`;

async function runMigrations() {
  const migrationsDir = path.join(__dirname, 'migrations');
  
  try {
    console.log('🔌 Connecting to Supabase...');
    await client.connect();
    console.log('✅ Connected!\n');

    // Create migrations tracking table
    await client.query(MIGRATIONS_TABLE);

    // Get already applied migrations
    const { rows: applied } = await client.query('SELECT name FROM _migrations');
    const appliedNames = new Set(applied.map(r => r.name));

    // Read migration files
    const files = fs.readdirSync(migrationsDir)
      .filter(f => f.endsWith('.sql'))
      .sort();

    if (files.length === 0) {
      console.log('📋 No migration files found.');
      return;
    }

    let newMigrations = 0;

    for (const file of files) {
      if (appliedNames.has(file)) {
        console.log(`⏭️  Skipping ${file} (already applied)`);
        continue;
      }

      const filePath = path.join(migrationsDir, file);
      const sql = fs.readFileSync(filePath, 'utf8');

      console.log(`🚀 Running ${file}...`);
      
      try {
        await client.query(sql);
        await client.query('INSERT INTO _migrations (name) VALUES ($1)', [file]);
        console.log(`✅ ${file} applied successfully`);
        newMigrations++;
      } catch (err) {
        console.error(`❌ Error in ${file}:`, err.message);
        // Continue with other migrations
      }
    }

    if (newMigrations === 0) {
      console.log('\n📋 All migrations already applied.');
    } else {
      console.log(`\n✅ Applied ${newMigrations} new migration(s).`);
    }

    // List all tables
    const { rows: tables } = await client.query(`
      SELECT table_name FROM information_schema.tables 
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
      ORDER BY table_name
    `);
    console.log('\n📋 Current tables:', tables.map(t => t.table_name).join(', '));

  } catch (error) {
    console.error('❌ Migration error:', error.message);
    process.exit(1);
  } finally {
    await client.end();
  }
}

runMigrations();







