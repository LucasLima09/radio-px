import { ref, watch } from 'vue';
import { defineStore } from 'pinia';

import { STORAGE_KEYS } from '@/core/config';
import { storage } from '@/core/storage';

export type Theme = 'light' | 'dark';

// public/theme-init.js já aplicou o tema antes do primeiro paint; partimos dele.
function resolveInitialTheme(): Theme {
  const current = document.documentElement.dataset.theme;
  if (current === 'dark' || current === 'light') return current;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export const useThemeStore = defineStore('theme', () => {
  const theme = ref<Theme>(resolveInitialTheme());

  watch(
    theme,
    (value) => {
      document.documentElement.dataset.theme = value;
    },
    { immediate: true },
  );

  function toggle(): void {
    theme.value = theme.value === 'dark' ? 'light' : 'dark';
    storage.set(STORAGE_KEYS.theme, theme.value);
  }

  return { theme, toggle };
});
