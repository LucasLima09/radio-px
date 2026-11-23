<script setup lang="ts">
import { computed } from 'vue';

import AppPagination from '@/components/AppPagination.vue';
import DataTable from '@/components/DataTable.vue';
import PageHeader from '@/components/PageHeader.vue';
import { POLL_INTERVAL_MS } from '@/core/config';
import { formatDateTime } from '@/utils/format';
import { useChannels } from './useChannels';

const {
  channels, total, totalPages, page, searchInput, deletingId, loaded, error, success,
  load, submitSearch, remove,
} = useChannels();

const columns = [
  { label: 'Canal' },
  { label: 'Dono' },
  { label: 'Tipo' },
  { label: 'Online agora' },
  { label: 'Criado em' },
  { label: 'Ações', class: 'actions-col' },
];
const meta = computed(
  () => `${total.value} canal(is) · atualiza a cada ${POLL_INTERVAL_MS / 1000}s${loaded.value ? '' : ' · carregando...'}`,
);
const emptyText = computed(() => {
  if (channels.value.length > 0 || error.value) return null;
  return loaded.value ? 'Nenhum canal encontrado.' : 'Carregando...';
});
</script>

<template>
  <div class="page">
    <PageHeader title="Canais" :meta="meta" :error="error" :success="success">
      <button class="ghost" @click="load">Atualizar</button>
    </PageHeader>

    <form class="filters" @submit.prevent="submitSearch">
      <label>
        Buscar
        <input v-model="searchInput" placeholder="Nome do canal" />
      </label>
      <button class="primary" type="submit">Filtrar</button>
    </form>

    <DataTable :columns="columns" :empty-text="emptyText">
      <tr v-for="c in channels" :key="c.id">
        <td class="cell-user">{{ c.name }}</td>
        <td>{{ c.owner || '—' }}</td>
        <td class="muted">{{ c.isPrivate ? 'Privado' : 'Público' }}</td>
        <td>
          <span class="badge" :class="c.online > 0 ? 'badge-live' : 'badge-off'">{{ c.online }} online</span>
        </td>
        <td class="muted">{{ formatDateTime(c.createdAt) }}</td>
        <td class="actions-col">
          <button
            class="danger"
            :disabled="deletingId != null || c.online > 0"
            :title="c.online > 0 ? 'Há pessoas conectadas neste canal' : 'Excluir canal'"
            @click="remove(c)"
          >
            {{ deletingId === c.id ? 'Excluindo...' : 'Excluir' }}
          </button>
        </td>
      </tr>
    </DataTable>

    <AppPagination v-model:page="page" :total-pages="totalPages" />
  </div>
</template>
