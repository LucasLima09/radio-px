import { useCallback, useEffect, useState } from 'react';

export type Theme = 'light' | 'dark';

export const THEME_KEY = 'radio_px_admin_theme';

function systemPrefersDark(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.matchMedia('(prefers-color-scheme: dark)').matches
  );
}

export function resolveInitialTheme(): Theme {
  if (typeof document === 'undefined') return 'light';
  const current = document.documentElement.dataset.theme;
  if (current === 'dark' || current === 'light') return current;
  return systemPrefersDark() ? 'dark' : 'light';
}

export function applyTheme(theme: Theme): void {
  document.documentElement.dataset.theme = theme;
}

export function useTheme() {
  const [theme, setTheme] = useState<Theme>(resolveInitialTheme);

  useEffect(() => {
    applyTheme(theme);
  }, [theme]);

  const toggle = useCallback(() => {
    setTheme((prev) => {
      const next: Theme = prev === 'dark' ? 'light' : 'dark';
      try {
        localStorage.setItem(THEME_KEY, next);
      } catch {
        /* armazenamento indisponível: segue apenas em memória */
      }
      return next;
    });
  }, []);

  return { theme, toggle };
}
