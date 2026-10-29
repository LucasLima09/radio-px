import { ref, watch } from 'vue';

import { useFeedback } from '@/composables/useFeedback';
import { locationsService } from '@/services/locations.service';
import { usersService } from '@/services/users.service';
import type { LocationReport, PublicUser } from '@/types';

export const LIMIT_OPTIONS = [100, 200, 500, 1000] as const;

export function useLocationLog() {
  const history = ref<LocationReport[]>([]);
  const users = ref<PublicUser[]>([]);
  const filterUserId = ref('');
  const limit = ref(200);
  const loaded = ref(false);
  const { error, fail } = useFeedback();

  async function refresh(): Promise<void> {
    try {
      const [log, allUsers] = await Promise.all([
        locationsService.history(filterUserId.value || undefined, limit.value),
        usersService.list(),
      ]);
      history.value = log;
      users.value = allUsers;
      error.value = null;
      loaded.value = true;
    } catch (e) {
      fail(e, 'Falha ao carregar o log');
    }
  }

  watch([filterUserId, limit], refresh, { immediate: true });

  return { history, users, filterUserId, limit, loaded, error, refresh };
}
