<script setup lang="ts">
import { computed, ref } from 'vue';

import AlertMessage from '@/components/AlertMessage.vue';
import MapView from '@/components/MapView.vue';
import { useNow } from '@/composables/useNow';
import type { DriverStatus } from '@/types';
import { formatTime, initial } from '@/utils/format';
import { STATUS_LABELS, driverName, driverReports, formatAgo } from './drivers';
import { useOverview } from './useOverview';

const { overview, updatedAt, error } = useOverview();
const now = useNow(15_000);

/** Status selecionado nos cards; null mostra todos os motoristas. */
const filter = ref<DriverStatus | null>(null);

const windowMinutes = computed(() => Math.round((overview.value?.beaconWindowSeconds ?? 180) / 60));

const stats = computed(() => {
  const counts = overview.value?.counts;
  return [
    { status: null, label: 'Motoristas', value: counts?.total, hint: 'Cadastrados, sem contar administradores' },
    { status: 'open' as const, label: STATUS_LABELS.open, value: counts?.open, hint: 'Conectados a um canal do rádio' },
    { status: 'closed' as const, label: STATUS_LABELS.closed, value: counts?.closed, hint: 'Fora do canal, com GPS ativo' },
    { status: 'offline' as const, label: STATUS_LABELS.offline, value: counts?.offline, hint: `Sem sinal há mais de ${windowMinutes.value} min` },
  ];
});

const drivers = computed(() => {
  const all = overview.value?.drivers ?? [];
  return filter.value ? all.filter((d) => d.status === filter.value) : all;
});

const reports = computed(() => driverReports(overview.value?.drivers ?? []));

const listTitle = computed(() => (filter.value ? STATUS_LABELS[filter.value] : 'Todos os motoristas'));
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
    <div class="stats-grid driver-stats">
      <button
        v-for="stat in stats"
        :key="stat.label"
        type="button"
        class="stat-card driver-stat"
        :class="[`is-${stat.status ?? 'all'}`, { 'is-active': filter === stat.status }]"
        :aria-pressed="filter === stat.status"
        @click="filter = stat.status"
      >
        <span class="driver-stat__label"><i class="driver-dot" />{{ stat.label }}</span>
        <strong>{{ stat.value ?? '—' }}</strong>
        <small>{{ stat.hint }}</small>
      </button>
    </div>
    <div class="overview-grid driver-grid">
      <section class="overview-map panel">
        <div class="panel-heading">
          <div><h3>Na estrada</h3><p>Última posição conhecida de cada motorista</p></div>
          <RouterLink v-slot="{ navigate }" :to="{ name: 'map' }" custom>
            <button class="ghost" @click="navigate">Abrir mapa ↗</button>
          </RouterLink>
        </div>
        <div class="map-container"><MapView :reports="reports" /></div>
      </section>
      <section class="panel driver-panel">
        <div class="panel-heading">
          <div><h3>{{ listTitle }}</h3><p>{{ drivers.length }} motorista(s)</p></div>
          <button v-if="filter" class="ghost" type="button" @click="filter = null">Ver todos</button>
        </div>
        <ul class="driver-list">
          <li v-for="d in drivers" :key="d.id" class="driver-row">
            <span class="driver-avatar">{{ initial(driverName(d)) }}</span>
            <div class="driver-info">
              <strong>{{ driverName(d) }}</strong>
              <span>
                {{ d.vehiclePlate || 'Sem placa' }} ·
                {{ d.status === 'open' && d.channel ? `Canal ${d.channel}` : `Último sinal ${formatAgo(d.lastSeenAt, now)}` }}
              </span>
            </div>
            <span class="badge" :class="`badge-driver-${d.status}`">{{ STATUS_LABELS[d.status] }}</span>
          </li>
          <li v-if="overview && drivers.length === 0" class="driver-empty">Nenhum motorista nesta situação.</li>
        </ul>
      </section>
    </div>
  </div>
</template>
