import { http } from '@/core/http/client';
import type { Orbit } from '@/types';

export interface OrbitPatch {
  name?: string;
  active?: boolean;
}

export const orbitsService = {
  list(): Promise<Orbit[]> {
    return http.get('/api/v1/admin/orbits');
  },
  update(id: string, patch: OrbitPatch): Promise<Orbit> {
    return http.patch(`/api/v1/admin/orbits/${id}`, patch);
  },
  remove(id: string): Promise<void> {
    return http.delete(`/api/v1/admin/orbits/${id}`);
  },
};
