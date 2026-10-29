<script setup lang="ts">
import { computed } from 'vue';

import AlertMessage from '@/components/AlertMessage.vue';
import MapView from '@/components/MapView.vue';
import { formatTime } from '@/utils/format';
import { useOverview } from './useOverview';

const { users, locations, updatedAt, error } = useOverview();

const stats = computed(() => [
  { label: 'Usuários', value: users.value?.length },
  { label: 'Localizações', value: locations.value?.length },
]);
</script>

<template>
  <div class="page overview-page">
    <div class="overview-heading">
      <div>
        <span class="eyebrow">CENTRAL DE OPERAÇÕES</span>
        <h2>Visão geral</h2>
        <p>Uma visão clara de quem está na estrada.</p>
      </div>
      <span class="update-label">
        {{ updatedAt ? `Atualizado às ${formatTime(updatedAt)}` : 'Carregando indicadores…' }}
      </span>
    </div>
    <AlertMessage :message="error" />
    <div class="stats-grid">
      <article v-for="stat in stats" :key="stat.label" class="stat-card">
        <span>{{ stat.label }}</span>
        <strong>{{ stat.value ?? '—' }}</strong>
      </article>
    </div>
    <div class="overview-grid">
      <section class="overview-map panel">
        <div class="panel-heading">
          <div><h3>Na estrada</h3><p>Últimas posições reportadas</p></div>
          <RouterLink v-slot="{ navigate }" :to="{ name: 'map' }" custom>
            <button class="ghost" @click="navigate">Abrir mapa ↗</button>
          </RouterLink>
        </div>
        <div class="map-container"><MapView :reports="locations ?? []" /></div>
      </section>
    </div>
  </div>
</template>
