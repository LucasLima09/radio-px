export const LIVE_LOCATION_MAX_AGE_MS = 60_000;

export function isLiveLocation(reportedAt: string, now = Date.now()): boolean {
  const age = now - Date.parse(reportedAt);
  return Number.isFinite(age) && age >= -5000 && age <= LIVE_LOCATION_MAX_AGE_MS;
}
