export const POLL_INTERVAL_MS = 5000;

export const DEV_SERVER = 'http://localhost:8080';

export const STORAGE_KEYS = {
  auth: 'radio_px_admin_auth',
  server: 'radio_px_admin_server',
  theme: 'radio_px_admin_theme',
} as const;

// Em desenvolvimento (Vite) aponta para o backend local.
// Servido pelo backend Go em /admin, usa a mesma origem.
export const IS_DEV = import.meta.env.DEV;

export const SERVER_PLACEHOLDER = IS_DEV ? DEV_SERVER : window.location.origin;

export function normalizeServer(server: string): string {
  return server.trim().replace(/\/+$/, '');
}
