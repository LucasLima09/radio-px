import type { Driver, DriverStatus, LocationReport } from '@/types';

export const STATUS_LABELS: Record<DriverStatus, string> = {
  open: 'App aberto',
  closed: 'App fechado',
  offline: 'Offline',
};

export function driverName(d: Driver): string {
  const full = `${d.firstName} ${d.lastName}`.trim();
  return full || d.username;
}

/** Posições para o mapa: a última conhecida de cada motorista, inclusive offline. */
export function driverReports(drivers: Driver[]): LocationReport[] {
  return drivers
    .filter((d) => d.lat != null && d.lng != null && d.lastSeenAt)
    .map((d) => ({
      userId: d.id,
      username: driverName(d),
      lat: d.lat!,
      lng: d.lng!,
      reportedAt: d.lastSeenAt!,
    }));
}

export function formatAgo(value: string | undefined, now: number): string {
  if (!value) return 'nunca enviou sinal';
  const seconds = Math.max(0, Math.round((now - Date.parse(value)) / 1000));
  if (!Number.isFinite(seconds)) return '—';
  if (seconds < 60) return 'agora há pouco';
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `há ${minutes} min`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `há ${hours} h`;
  const days = Math.round(hours / 24);
  return days === 1 ? 'há 1 dia' : `há ${days} dias`;
}
