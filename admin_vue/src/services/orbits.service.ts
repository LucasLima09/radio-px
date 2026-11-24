import { http } from '@/core/http/client';
import type { Orbit } from '@/types';

export interface OrbitInput {
  name: string;
  identifier: string;
}

export const orbitsService = {
  list(): Promise<Orbit[]> {
    return http.get('/api/v1/admin/orbits');
  },
  create(input: OrbitInput): Promise<Orbit> {
    return http.post('/api/v1/admin/orbits', input);
  },
  update(id: string, patch: Partial<OrbitInput & { active: boolean }>): Promise<Orbit> {
    return http.patch(`/api/v1/admin/orbits/${id}`, patch);
  },
  remove(id: string): Promise<void> {
    return http.delete(`/api/v1/admin/orbits/${id}`);
  },
};
