import { watch } from 'vue';
import { createRouter, createWebHistory } from 'vue-router';

import { useAuthStore } from '@/stores/auth.store';
import { routes } from './routes';

export const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
});

router.beforeEach((to) => {
  const auth = useAuthStore();
  if (!to.meta.public && !auth.isAuthenticated) return { name: 'login' };
  if (to.name === 'login' && auth.isAuthenticated) return { name: 'overview' };
  return true;
});

/** Sessão encerrada em qualquer ponto (logout, refresh negado, 401/403) volta para o login. */
export function installSessionRedirect(): void {
  const auth = useAuthStore();
  watch(
    () => auth.isAuthenticated,
    (authenticated) => {
      if (!authenticated && !router.currentRoute.value.meta.public) {
        void router.replace({ name: 'login' });
      }
    },
  );
}
