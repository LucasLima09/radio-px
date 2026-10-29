<script setup lang="ts">
import type { Role, PublicUser } from '@/types';
import { formatDateTime } from '@/utils/format';
import type { UserDraft } from './useUsers';

defineProps<{
  user: PublicUser;
  draft: UserDraft;
  hasDraft: boolean;
  dirty: boolean;
  isSelf: boolean;
  busy: boolean;
  saving: boolean;
  deleting: boolean;
}>();

defineEmits<{
  edit: [patch: Partial<UserDraft>];
  save: [];
  cancel: [];
  remove: [];
}>();

const roles: Role[] = ['user', 'admin'];
</script>

<template>
  <tr>
    <td>
      <input
        class="inline-input"
        :value="draft.username"
        @input="$emit('edit', { username: ($event.target as HTMLInputElement).value })"
      />
    </td>
    <td>
      <select
        class="inline-select"
        :value="draft.role"
        @change="$emit('edit', { role: ($event.target as HTMLSelectElement).value })"
      >
        <option v-for="role in roles" :key="role" :value="role">{{ role }}</option>
      </select>
    </td>
    <td class="muted">{{ formatDateTime(user.createdAt) }}</td>
    <td class="actions-col">
      <div class="inline-actions">
        <button v-if="dirty" class="primary" :disabled="busy" @click="$emit('save')">
          {{ saving ? 'Salvando...' : 'Salvar' }}
        </button>
        <button v-if="hasDraft" class="ghost" :disabled="busy" @click="$emit('cancel')">Cancelar</button>
        <button
          class="danger"
          :disabled="busy || isSelf"
          :title="isSelf ? 'Você não pode excluir sua própria conta' : 'Excluir usuário'"
          @click="$emit('remove')"
        >
          {{ deleting ? 'Excluindo...' : 'Excluir' }}
        </button>
      </div>
    </td>
  </tr>
</template>
