import { ref } from 'vue';

import { POLL_INTERVAL_MS } from '@/core/config';
import { useFeedback } from '@/composables/useFeedback';
import { usePolling } from '@/composables/usePolling';
import { locationsService } from '@/services/locations.service';
import { usersService } from '@/services/users.service';
import type { LocationReport, PublicUser } from '@/types';

export function useOverview() {
  const users = ref<PublicUser[] | null>(null);
  const locations = ref<LocationReport[] | null>(null);
  const updatedAt = ref<Date | null>(null);
  const { error, fail } = useFeedback();

  usePolling(async () => {
    try {
      const [u, l] = await Promise.all([usersService.list(), locationsService.latest()]);
      users.value = u;
      locations.value = l;
      updatedAt.value = new Date();
      error.value = null;
    } catch (e) {
      fail(e, 'Falha ao carregar o resumo');
    }
  }, POLL_INTERVAL_MS);

  return { users, locations, updatedAt, error };
}
