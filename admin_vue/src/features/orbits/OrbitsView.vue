<script setup lang="ts">
import { computed } from 'vue';

import DataTable from '@/components/DataTable.vue';
import PageHeader from '@/components/PageHeader.vue';
import { formatDateTime } from '@/utils/format';
import { useOrbits } from './useOrbits';

const {
  orbits, loaded, busyId, editingId, draft, error, success,
  load, startEdit, cancelEdit, saveEdit, toggleActive, remove,
} = useOrbits();

const columns = [
  { label: 'Nome' },
  { label: 'Id' },
  { label: 'Status' },
  { label: 'Última posição' },
  { label: 'Último sinal' },
  { label: 'Ações', class: 'actions-col' },
];
const meta = computed(() => `${orbits.value.length} Orbit(s)${loaded.value ? '' : ' · carregando...'}`);
const emptyText = computed(() => {
  if (orbits.value.length > 0 || error.value) return null;
  return loaded.value ? 'Nenhum Orbit encontrado ainda. Eles aparecem aqui no primeiro sinal válido.' : 'Carregando...';
});
</script>

<template>
  <div class="page">
    <PageHeader title="Orbits" :meta="meta" :error="error" :success="success">
      <button class="ghost" @click="load">Atualizar</button>
    </PageHeader>

    <DataTable :columns="columns" :empty-text="emptyText">
      <tr v-for="o in orbits" :key="o.id">
        <td v-if="editingId === o.id"><input v-model="draft" class="inline-input" maxlength="64" /></td>
        <td v-else class="cell-user">{{ o.name }}</td>
        <td class="mono">{{ o.identifier }}</td>
        <td>
          <span class="badge" :class="o.active ? 'badge-live' : 'badge-off'">{{ o.active ? 'Ativo' : 'Inativo' }}</span>
        </td>
        <td class="mono">{{ o.last ? `${o.last.lat.toFixed(5)}, ${o.last.lng.toFixed(5)}` : '—' }}</td>
        <td class="muted">{{ o.last ? formatDateTime(o.last.at) : '—' }}</td>
        <td class="actions-col">
          <div class="inline-actions">
            <template v-if="editingId === o.id">
              <button class="primary" :disabled="busyId != null" @click="saveEdit(o)">
                {{ busyId === o.id ? 'Salvando...' : 'Salvar' }}
              </button>
              <button class="ghost" :disabled="busyId != null" @click="cancelEdit">Cancelar</button>
            </template>
            <template v-else>
              <button class="ghost" :disabled="busyId != null" @click="startEdit(o)">Editar</button>
              <button class="ghost" :disabled="busyId != null" @click="toggleActive(o)">
                {{ o.active ? 'Desativar' : 'Ativar' }}
              </button>
              <button class="danger" :disabled="busyId != null" @click="remove(o)">Excluir</button>
            </template>
          </div>
        </td>
      </tr>
    </DataTable>
  </div>
</template>
