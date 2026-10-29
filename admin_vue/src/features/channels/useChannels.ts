import { computed, ref, watch } from 'vue';

import { POLL_INTERVAL_MS } from '@/core/config';
import { useFeedback } from '@/composables/useFeedback';
import { usePolling } from '@/composables/usePolling';
import { channelsService } from '@/services/channels.service';
import type { AdminChannel, Page } from '@/types';

const DEFAULT_PAGE_SIZE = 20;

export function useChannels() {
  const data = ref<Page<AdminChannel> | null>(null);
  const searchInput = ref('');
  const search = ref('');
  const page = ref(1);
  const deletingId = ref<string | null>(null);
  const loaded = ref(false);
  const { error, success, clear, fail, succeed } = useFeedback();

  const channels = computed(() => data.value?.items ?? []);
  const total = computed(() => data.value?.total ?? 0);
  const totalPages = computed(() =>
    Math.max(1, Math.ceil(total.value / (data.value?.pageSize ?? DEFAULT_PAGE_SIZE))),
  );

  async function load(): Promise<void> {
    try {
      data.value = await channelsService.list(search.value, page.value);
      error.value = null;
      loaded.value = true;
    } catch (e) {
      fail(e, 'Falha ao listar canais');
    }
  }

  const polling = usePolling(load, POLL_INTERVAL_MS);
  watch([search, page], polling.restart);

  function submitSearch(): void {
    page.value = 1;
    search.value = searchInput.value.trim();
  }

  async function remove(channel: AdminChannel): Promise<void> {
    if (!window.confirm(`Excluir o canal "${channel.name}"? Esta ação não pode ser desfeita.`)) return;
    deletingId.value = channel.id;
    clear();
    try {
      await channelsService.remove(channel.id);
      succeed(`Canal "${channel.name}" excluído.`);
      await load();
    } catch (e) {
      fail(e, 'Falha ao excluir o canal');
    } finally {
      deletingId.value = null;
    }
  }

  return {
    channels, total, totalPages, page, searchInput, deletingId, loaded, error, success,
    load, submitSearch, remove,
  };
}
