import { computed, onMounted, ref } from 'vue';

import { useFeedback } from '@/composables/useFeedback';
import { usersService, type UserPatch } from '@/services/users.service';
import { useAuthStore } from '@/stores/auth.store';
import type { PublicUser } from '@/types';

export type UserDraft = Required<UserPatch>;

export function useUsers() {
  const auth = useAuthStore();
  const users = ref<PublicUser[]>([]);
  const drafts = ref<Record<string, UserDraft>>({});
  const savingId = ref<string | null>(null);
  const deletingId = ref<string | null>(null);
  const loaded = ref(false);
  const { error, success, clear, fail, succeed } = useFeedback();

  const busy = computed(() => savingId.value != null || deletingId.value != null);

  async function load(): Promise<void> {
    try {
      users.value = await usersService.list();
      drafts.value = {};
      error.value = null;
      loaded.value = true;
    } catch (e) {
      fail(e, 'Falha ao listar usuários');
    }
  }

  function draftOf(u: PublicUser): UserDraft {
    return drafts.value[u.id] ?? { username: u.username, role: u.role ?? 'user' };
  }

  function editDraft(u: PublicUser, patch: Partial<UserDraft>): void {
    drafts.value[u.id] = { ...draftOf(u), ...patch };
  }

  function resetDraft(u: PublicUser): void {
    delete drafts.value[u.id];
  }

  function isDirty(u: PublicUser): boolean {
    const draft = drafts.value[u.id];
    return draft !== undefined && (draft.username !== u.username || draft.role !== (u.role ?? 'user'));
  }

  function isSelf(u: PublicUser): boolean {
    return u.id === auth.user?.id;
  }

  async function save(u: PublicUser): Promise<void> {
    const draft = drafts.value[u.id];
    if (!draft) return;
    savingId.value = u.id;
    clear();
    try {
      const updated = await usersService.update(u.id, draft);
      users.value = users.value.map((x) => (x.id === u.id ? { ...x, ...updated } : x));
      resetDraft(u);
      succeed(`Usuário "${updated.username}" atualizado.`);
    } catch (e) {
      fail(e, 'Falha ao salvar');
    } finally {
      savingId.value = null;
    }
  }

  async function remove(u: PublicUser): Promise<void> {
    const confirmed = window.confirm(
      `Excluir o usuário "${u.username}"? Isso remove também os canais, posições e tokens dele. Esta ação não pode ser desfeita.`,
    );
    if (!confirmed) return;
    deletingId.value = u.id;
    clear();
    try {
      await usersService.remove(u.id);
      users.value = users.value.filter((x) => x.id !== u.id);
      resetDraft(u);
      succeed(`Usuário "${u.username}" excluído.`);
    } catch (e) {
      fail(e, 'Falha ao excluir');
    } finally {
      deletingId.value = null;
    }
  }

  onMounted(load);

  return {
    users, drafts, savingId, deletingId, loaded, busy, error, success,
    load, draftOf, editDraft, resetDraft, isDirty, isSelf, save, remove,
  };
}
