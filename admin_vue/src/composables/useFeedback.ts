import { ref } from 'vue';

import { errorMessage, isUnauthorized } from '@/core/http/errors';

/**
 * Mensagens de erro/sucesso de uma tela. Erros de sessão (401/403) são ignorados:
 * o client já encerrou a sessão e o router leva para o login.
 */
export function useFeedback() {
  const error = ref<string | null>(null);
  const success = ref<string | null>(null);

  function clear(): void {
    error.value = null;
    success.value = null;
  }

  function fail(e: unknown, fallback: string): void {
    if (isUnauthorized(e)) return;
    error.value = errorMessage(e, fallback);
  }

  function succeed(message: string): void {
    success.value = message;
  }

  return { error, success, clear, fail, succeed };
}
