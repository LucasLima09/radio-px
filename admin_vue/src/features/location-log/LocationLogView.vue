<script setup lang="ts">
import { computed } from 'vue';

import DataTable from '@/components/DataTable.vue';
import PageHeader from '@/components/PageHeader.vue';
import { formatCoord, formatDateTime } from '@/utils/format';
import { LIMIT_OPTIONS, useLocationLog } from './useLocationLog';

const { history, users, filterUserId, limit, loaded, error, refresh } = useLocationLog();

const columns = [{ label: 'Motorista' }, { label: 'Latitude' }, { label: 'Longitude' }, { label: 'Horário' }];
const meta = computed(() => `${history.value.length} registro(s)${loaded.value ? '' : ' · carregando...'}`);
const emptyText = computed(() => {
  if (history.value.length > 0 || error.value) return null;
  return loaded.value ? 'Nenhuma posição registrada.' : 'Carregando...';
});
</script>

<template>
  <div class="page">
    <PageHeader title="Log de posições" :meta="meta" :error="error" />

    <div class="filters">
      <label>
        Motorista
        <select v-model="filterUserId">
          <option value="">Todos</option>
          <option v-for="u in users" :key="u.id" :value="u.id">{{ u.username }}</option>
        </select>
      </label>
      <label>
        Máximo
        <select v-model.number="limit">
          <option v-for="n in LIMIT_OPTIONS" :key="n" :value="n">{{ n }}</option>
        </select>
      </label>
      <button class="ghost" @click="refresh">Recarregar</button>
    </div>

    <DataTable :columns="columns" :empty-text="emptyText">
      <tr v-for="(r, i) in history" :key="`${r.userId}-${r.reportedAt}-${i}`">
        <td class="cell-user">{{ r.username }}</td>
        <td class="mono">{{ formatCoord(r.lat) }}</td>
        <td class="mono">{{ formatCoord(r.lng) }}</td>
        <td class="muted">{{ formatDateTime(r.reportedAt) }}</td>
      </tr>
    </DataTable>
  </div>
</template>
