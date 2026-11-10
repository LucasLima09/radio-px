import { ref } from 'vue';

import { POLL_INTERVAL_MS } from '@/core/config';
import { useFeedback } from '@/composables/useFeedback';
import { usePolling } from '@/composables/usePolling';
import { driversService } from '@/services/drivers.service';
import type { DriversOverview } from '@/types';

export function useOverview() {
  const overview = ref<DriversOverview | null>(null);
  const updatedAt = ref<Date | null>(null);
  const { error, fail } = useFeedback();

  usePolling(async () => {
    try {
      overview.value = await driversService.overview();
      updatedAt.value = new Date();
      error.value = null;
    } catch (e) {
      fail(e, 'Falha ao carregar o resumo');
    }
  }, POLL_INTERVAL_MS);

  return { overview, updatedAt, error };
}
