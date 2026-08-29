import pg from 'pg';
import 'dotenv/config';

// DATABASE_SSL=1 pour un Postgres managé (Supabase, etc.) — TLS exigé.
export const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  ssl: process.env.DATABASE_SSL === '1' ? { rejectUnauthorized: false } : undefined,
});

export const q = (text, params) => pool.query(text, params);
