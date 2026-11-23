<script setup lang="ts">
import { ref } from 'vue';

import MapView from '@/components/MapView.vue';
import PageHeader from '@/components/PageHeader.vue';
import { POLL_INTERVAL_MS } from '@/core/config';
import { useFeedback } from '@/composables/useFeedback';
import { usePolling } from '@/composables/usePolling';
import { locationsService } from '@/services/locations.service';
import type { LocationReport } from '@/types';

const reports = ref<LocationReport[]>([]);
const { error, fail } = useFeedback();

usePolling(async () => {
  try {
    reports.value = await locationsService.latest();
    error.value = null;
  } catch (e) {
    fail(e, 'Falha ao buscar as posições');
  }
}, POLL_INTERVAL_MS);
</script>

<template>
  <div class="page">
    <PageHeader
      title="Mapa ao vivo"
      :meta="`${reports.length} posição(ões) · atualiza a cada ${POLL_INTERVAL_MS / 1000}s`"
      :error="error"
    />
    <div class="map-container"><MapView :reports="reports" /></div>
  </div>
</template>
