<script setup lang="ts">
import { computed } from 'vue';

import DataTable from '@/components/DataTable.vue';
import PageHeader from '@/components/PageHeader.vue';
import { formatDateTime } from '@/utils/format';
import { useOrbits } from './useOrbits';

const {
  orbits, loaded, busyId, creating, form, editingId, draft, error, success,
  load, create, startEdit, cancelEdit, saveEdit, toggleActive, remove,
} = useOrbits();

const columns = [
  { label: 'Nome' },
  { label: 'Identificador Bluetooth' },
  { label: 'Status' },
  { label: 'Cadastrado em' },
  { label: 'Ações', class: 'actions-col' },
];
const meta = computed(() => `${orbits.value.length} Orbit(s)${loaded.value ? '' : ' · carregando...'}`);
const emptyText = computed(() => {
  if (orbits.value.length > 0 || error.value) return null;
  return loaded.value ? 'Nenhum Orbit cadastrado.' : 'Carregando...';
});
const canCreate = computed(() => form.name.trim() !== '' && form.identifier.trim() !== '' && !creating.value);
</script>

<template>
  <div class="page">
    <PageHeader title="Orbits" :meta="meta" :error="error" :success="success">
      <button class="ghost" @click="load">Atualizar</button>
    </PageHeader>

    <form class="filters" @submit.prevent="create">
      <label>
        Nome
        <input v-model="form.name" maxlength="64" placeholder="Orbit do caminhão 12" />
      </label>
      <label title="Nome exato que o dispositivo anuncia no Bluetooth">
        Identificador Bluetooth
        <input v-model="form.identifier" maxlength="64" placeholder="ORBIT-12" />
      </label>
      <button class="primary" type="submit" :disabled="!canCreate">
        {{ creating ? 'Cadastrando...' : 'Cadastrar Orbit' }}
      </button>
    </form>

    <DataTable :columns="columns" :empty-text="emptyText">
      <tr v-for="o in orbits" :key="o.id">
        <template v-if="editingId === o.id">
          <td><input v-model="draft.name" class="inline-input" maxlength="64" /></td>
          <td><input v-model="draft.identifier" class="inline-input mono" maxlength="64" /></td>
        </template>
        <template v-else>
          <td class="cell-user">{{ o.name }}</td>
          <td class="mono">{{ o.identifier }}</td>
        </template>
        <td>
          <span class="badge" :class="o.active ? 'badge-live' : 'badge-off'">{{ o.active ? 'Ativo' : 'Inativo' }}</span>
        </td>
        <td class="muted">{{ formatDateTime(o.createdAt) }}</td>
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
