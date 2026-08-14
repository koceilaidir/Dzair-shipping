// Crée le premier compte admin :  npm run create-admin -- email@exemple.com "MotDePasseFort" "Ton Nom"
import bcrypt from 'bcryptjs';
import { pool } from '../src/db.js';

const [email, password, nom] = process.argv.slice(2);
if (!email || !password || !nom) {
  console.log('Usage : npm run create-admin -- email motdepasse "Nom complet"');
  process.exit(1);
}
if (password.length < 10) {
  console.log('⚠ Mot de passe trop court — 10 caractères minimum.');
  process.exit(1);
}

const hash = await bcrypt.hash(password, 12);
await pool.query(
  `INSERT INTO users (email, password_hash, role, nom) VALUES ($1,$2,'admin',$3)
   ON CONFLICT (email) DO NOTHING`,
  [email.toLowerCase(), hash, nom],
);
console.log(`✓ Admin créé : ${email}`);
await pool.end();
