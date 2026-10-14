-- Todos os usuários nascem como "user"; um admin é promovido manualmente:
--   UPDATE users SET role = 'admin' WHERE username = '...';
ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user';
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);