export const POLL_INTERVAL_MS = 5000;

export const STORAGE_KEYS = {
  auth: 'radio_px_admin_auth',
  theme: 'radio_px_admin_theme',
} as const;

// Em desenvolvimento (Vite) aponta para o backend local.
// Servido pelo backend Go em /admin, usa a mesma origem.
export const API_BASE_URL = import.meta.env.DEV ? 'http://localhost:8080' : '';
