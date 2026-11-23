import { describe, expect, it } from 'vitest';

import type { Driver } from '@/types';
import { driverName, driverReports, formatAgo } from './drivers';

const base: Driver = {
  id: '1',
  username: 'joao.silva',
  firstName: 'João',
  lastName: 'Silva',
  vehiclePlate: 'ABC1D23',
  status: 'open',
  lat: -23.5,
  lng: -46.6,
  lastSeenAt: '2026-10-29T12:00:00Z',
};

describe('driverName', () => {
  it('usa nome e sobrenome, com o usuário como reserva', () => {
    expect(driverName(base)).toBe('João Silva');
    expect(driverName({ ...base, firstName: '', lastName: '' })).toBe('joao.silva');
  });
});

describe('driverReports', () => {
  it('leva ao mapa todo motorista com posição, inclusive offline', () => {
    const reports = driverReports([
      base,
      { ...base, id: '2', status: 'closed' },
      { ...base, id: '3', status: 'offline' },
      { ...base, id: '4', status: 'open', lat: undefined, lng: undefined },
    ]);
    expect(reports.map((r) => r.userId)).toEqual(['1', '2', '3']);
    expect(reports[0].username).toBe('João Silva');
  });
});

describe('formatAgo', () => {
  const now = Date.parse('2026-10-29T12:00:00Z');

  it('descreve o tempo desde o último sinal', () => {
    expect(formatAgo('2026-10-29T11:59:30Z', now)).toBe('agora há pouco');
    expect(formatAgo('2026-10-29T11:55:00Z', now)).toBe('há 5 min');
    expect(formatAgo('2026-10-29T09:00:00Z', now)).toBe('há 3 h');
    expect(formatAgo('2026-10-27T12:00:00Z', now)).toBe('há 2 dias');
    expect(formatAgo(undefined, now)).toBe('nunca enviou sinal');
  });
});
