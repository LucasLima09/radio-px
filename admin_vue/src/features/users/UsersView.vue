<script setup lang="ts">
import { computed } from 'vue';

import DataTable from '@/components/DataTable.vue';
import PageHeader from '@/components/PageHeader.vue';
import UserRow from './UserRow.vue';
import { useUsers } from './useUsers';

const {
  users, drafts, savingId, deletingId, loaded, busy, error, success,
  load, draftOf, editDraft, resetDraft, isDirty, isSelf, save, remove,
} = useUsers();

const columns = [{ label: 'Usuário' }, { label: 'Role' }, { label: 'Criado em' }, { label: 'Ações', class: 'actions-col' }];
const meta = computed(() => `${users.value.length} cadastrado(s)${loaded.value ? '' : ' · carregando...'}`);
const emptyText = computed(() => (users.value.length === 0 && !error.value ? 'Nenhum usuário cadastrado.' : null));
</script>

<template>
  <div class="page">
    <PageHeader title="Usuários" :meta="meta" :error="error" :success="success">
      <button class="ghost" @click="load">Atualizar</button>
    </PageHeader>

    <DataTable :columns="columns" :empty-text="emptyText">
      <UserRow
        v-for="u in users"
        :key="u.id"
        :user="u"
        :draft="draftOf(u)"
        :has-draft="u.id in drafts"
        :dirty="isDirty(u)"
        :is-self="isSelf(u)"
        :busy="busy"
        :saving="savingId === u.id"
        :deleting="deletingId === u.id"
        @edit="editDraft(u, $event)"
        @save="save(u)"
        @cancel="resetDraft(u)"
        @remove="remove(u)"
      />
    </DataTable>
  </div>
</template>
