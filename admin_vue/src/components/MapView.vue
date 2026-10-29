<script setup lang="ts">
import { ref, toRef } from 'vue';
import 'leaflet/dist/leaflet.css';

import { useLeafletMap } from '@/composables/useLeafletMap';
import { useNow } from '@/composables/useNow';
import type { LocationReport } from '@/types';

const props = defineProps<{ reports: LocationReport[] }>();

const container = ref<HTMLElement | null>(null);
const now = useNow();
useLeafletMap(container, toRef(props, 'reports'), now);
</script>

<template>
  <div ref="container" class="leaflet-container" />
  <div class="map-legend" aria-label="Status da localização">
    <span><i class="legend-live" />Em tempo real</span>
    <span><i class="legend-stale" />Sem atualização recente</span>
    <small>Tempo real: posição recebida há até 1 minuto</small>
  </div>
</template>
