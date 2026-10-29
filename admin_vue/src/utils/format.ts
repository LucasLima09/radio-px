export function formatDateTime(value?: string): string {
  return value ? new Date(value).toLocaleString('pt-BR') : '—';
}

export function formatTime(value: Date): string {
  return value.toLocaleTimeString('pt-BR');
}

export function formatCoord(value: number, digits = 6): string {
  return value.toFixed(digits);
}

export function initial(name?: string, fallback = '?'): string {
  return name?.[0]?.toUpperCase() ?? fallback;
}
