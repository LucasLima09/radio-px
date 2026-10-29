import { http } from '@/core/http/client';
import type { AdminChannel, Page } from '@/types';

export const channelsService = {
  list(search = '', page = 1): Promise<Page<AdminChannel>> {
    const params = new URLSearchParams();
    if (search) params.set('q', search);
    params.set('page', String(page));
    return http.get(`/api/v1/admin/channels?${params.toString()}`);
  },
  remove(id: string): Promise<void> {
    return http.delete(`/api/v1/admin/channels/${id}`);
  },
};
