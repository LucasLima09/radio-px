import { computed, ref } from 'vue';
import { defineStore } from 'pinia';

import { DEV_SERVER, IS_DEV, STORAGE_KEYS, normalizeServer } from '@/core/config';
import { http } from '@/core/http/client';
import { storage } from '@/core/storage';
import { authService } from '@/services/auth.service';
import type { AuthSession } from '@/types';

function initialServer(): string {
  // Servido pelo backend: mesma origem. Em dev: último servidor usado.
  if (!IS_DEV) return '';
  return storage.get(STORAGE_KEYS.server) ?? DEV_SERVER;
}

export const useAuthStore = defineStore('auth', () => {
  const server = ref(initialServer());
  const session = ref<AuthSession | null>(storage.getJSON<AuthSession>(STORAGE_KEYS.auth));

  const isAuthenticated = computed(() => session.value != null);
  const user = computed(() => session.value?.user ?? null);

  function applySession(next: AuthSession): void {
    session.value = next;
    storage.setJSON(STORAGE_KEYS.auth, next);
  }

  function clearSession(): void {
    session.value = null;
    storage.remove(STORAGE_KEYS.auth);
  }

  async function login(serverUrl: string, username: string, password: string): Promise<void> {
    const normalized = normalizeServer(serverUrl);
    const previous = server.value;
    server.value = normalized;
    try {
      applySession(await authService.login(username, password));
      storage.set(STORAGE_KEYS.server, normalized);
    } catch (e) {
      server.value = previous;
      throw e;
    }
  }

  async function refresh(): Promise<boolean> {
    const refreshToken = session.value?.refreshToken;
    if (!refreshToken) return false;
    try {
      applySession(await authService.refresh(refreshToken));
      return true;
    } catch {
      clearSession();
      return false;
    }
  }

  async function logout(): Promise<void> {
    await authService.logout().catch(() => {});
    clearSession();
  }

  http.setAuthBridge({
    baseUrl: () => server.value,
    accessToken: () => session.value?.accessToken ?? null,
    refresh,
    onUnauthorized: clearSession,
  });

  return { server, user, isAuthenticated, login, logout };
});
