import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { effectScope } from 'vue';

import { usePolling } from './usePolling';

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe('usePolling', () => {
  it('executa imediatamente, repete e para ao descartar o escopo', async () => {
    const task = vi.fn(async () => {});
    const scope = effectScope();
    scope.run(() => usePolling(task, 1000));
    expect(task).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(2000);
    expect(task).toHaveBeenCalledTimes(3);
    scope.stop();
    await vi.advanceTimersByTimeAsync(5000);
    expect(task).toHaveBeenCalledTimes(3);
  });

  it('não sobrepõe execuções lentas', async () => {
    let finish!: () => void;
    const task = vi.fn(() => new Promise<void>((r) => (finish = r)));
    const scope = effectScope();
    scope.run(() => usePolling(task, 1000));
    await vi.advanceTimersByTimeAsync(3000);
    expect(task).toHaveBeenCalledTimes(1);
    finish();
    await vi.advanceTimersByTimeAsync(1000);
    expect(task).toHaveBeenCalledTimes(2);
    scope.stop();
  });
});
