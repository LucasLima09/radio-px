import { http } from '@/core/http/client';
import type { PublicUser } from '@/types';

export type UserPatch = Pick<PublicUser, 'username' | 'role'>;

export const usersService = {
  list(): Promise<PublicUser[]> {
    return http.get('/api/v1/admin/users');
  },
  update(id: string, patch: UserPatch): Promise<PublicUser> {
    return http.patch(`/api/v1/admin/users/${id}`, patch);
  },
  remove(id: string): Promise<void> {
    return http.delete(`/api/v1/admin/users/${id}`);
  },
};
