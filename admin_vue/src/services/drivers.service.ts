import { http } from '@/core/http/client';
import type { DriversOverview } from '@/types';

export const driversService = {
  overview(): Promise<DriversOverview> {
    return http.get('/api/v1/admin/drivers');
  },
};
