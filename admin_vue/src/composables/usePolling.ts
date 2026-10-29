import { onScopeDispose } from 'vue';

/**
 * Executa `task` imediatamente e a cada `intervalMs`, sem sobrepor execuções.
 * Para sozinho quando o componente é desmontado.
 */
export function usePolling(task: () => Promise<unknown>, intervalMs: number) {
  let pending = false;
  let timer: ReturnType<typeof setInterval> | undefined;

  async function run(): Promise<void> {
    if (pending) return;
    pending = true;
    try {
      await task();
    } finally {
      pending = false;
    }
  }

  function stop(): void {
    clearInterval(timer);
    timer = undefined;
  }

  /** Executa agora e reinicia o intervalo (ex.: quando um filtro muda). */
  function restart(): void {
    stop();
    void run();
    timer = setInterval(run, intervalMs);
  }

  restart();
  onScopeDispose(stop);

  return { run, restart, stop };
}
