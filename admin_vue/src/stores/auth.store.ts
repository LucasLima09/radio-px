import { computed, ref } from 'vue';
import { defineStore } from 'pinia';

import { API_BASE_URL, STORAGE_KEYS } from '@/core/config';
import { http } from '@/core/http/client';
import { storage } from '@/core/storage';
import { authService } from '@/services/auth.service';
import type { AuthSession } from '@/types';

export const useAuthStore = defineStore('auth', () => {
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

  async function login(username: string, password: string): Promise<void> {
    applySession(await authService.login(username, password));
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
    baseUrl: () => API_BASE_URL,
    accessToken: () => session.value?.accessToken ?? null,
    refresh,
    onUnauthorized: clearSession,
  });

  return { user, isAuthenticated, login, logout };
});
