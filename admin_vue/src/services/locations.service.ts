import { http } from '@/core/http/client';
import type { LocationReport } from '@/types';

export const locationsService = {
  latest(): Promise<LocationReport[]> {
    return http.get('/api/v1/admin/locations');
  },
  history(userId?: string, limit = 200): Promise<LocationReport[]> {
    const params = new URLSearchParams();
    if (userId) params.set('userId', userId);
    params.set('limit', String(limit));
    return http.get(`/api/v1/admin/locations/history?${params.toString()}`);
  },
};
