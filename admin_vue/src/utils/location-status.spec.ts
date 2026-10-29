import { describe, expect, it } from 'vitest';

import { isLiveLocation } from './location-status';

describe('isLiveLocation', () => {
  const now = Date.parse('2026-10-28T12:00:00Z');

  it('considera ao vivo até 1 minuto', () => {
    expect(isLiveLocation('2026-10-28T11:59:30Z', now)).toBe(true);
    expect(isLiveLocation('2026-10-28T11:59:00Z', now)).toBe(true);
  });

  it('considera parado depois de 1 minuto', () => {
    expect(isLiveLocation('2026-10-28T11:58:59Z', now)).toBe(false);
  });

  it('tolera pequeno desvio de relógio e rejeita datas inválidas', () => {
    expect(isLiveLocation('2026-10-28T12:00:04Z', now)).toBe(true);
    expect(isLiveLocation('2026-10-28T12:00:10Z', now)).toBe(false);
    expect(isLiveLocation('invalida', now)).toBe(false);
  });
});
