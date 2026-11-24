import { reactive, ref } from 'vue';

import { confirmDialog } from '@/composables/useConfirm';
import { useFeedback } from '@/composables/useFeedback';
import { orbitsService, type OrbitInput } from '@/services/orbits.service';
import type { Orbit } from '@/types';

export function useOrbits() {
  const orbits = ref<Orbit[]>([]);
  const loaded = ref(false);
  const busyId = ref<string | null>(null);
  const creating = ref(false);
  const form = reactive<OrbitInput>({ name: '', identifier: '' });
  /** Orbit em edição e o rascunho dos campos. */
  const editingId = ref<string | null>(null);
  const draft = reactive<OrbitInput>({ name: '', identifier: '' });
  const { error, success, clear, fail, succeed } = useFeedback();

  async function load(): Promise<void> {
    try {
      orbits.value = await orbitsService.list();
      error.value = null;
      loaded.value = true;
    } catch (e) {
      fail(e, 'Falha ao listar os Orbits');
    }
  }

  async function create(): Promise<void> {
    if (creating.value) return;
    creating.value = true;
    clear();
    try {
      const orbit = await orbitsService.create({ name: form.name.trim(), identifier: form.identifier.trim() });
      form.name = '';
      form.identifier = '';
      succeed(`Orbit "${orbit.name}" cadastrado. Os apps já podem reconhecê-lo.`);
      await load();
    } catch (e) {
      fail(e, 'Falha ao cadastrar o Orbit');
    } finally {
      creating.value = false;
    }
  }

  function startEdit(orbit: Orbit): void {
    editingId.value = orbit.id;
    draft.name = orbit.name;
    draft.identifier = orbit.identifier;
  }

  function cancelEdit(): void {
    editingId.value = null;
  }

  async function run(orbit: Orbit, action: () => Promise<unknown>, done: string, failure: string): Promise<void> {
    busyId.value = orbit.id;
    clear();
    try {
      await action();
      succeed(done);
      await load();
    } catch (e) {
      fail(e, failure);
    } finally {
      busyId.value = null;
    }
  }

  async function saveEdit(orbit: Orbit): Promise<void> {
    await run(
      orbit,
      () => orbitsService.update(orbit.id, { name: draft.name.trim(), identifier: draft.identifier.trim() }),
      'Orbit atualizado.',
      'Falha ao salvar o Orbit',
    );
    if (!error.value) editingId.value = null;
  }

  function toggleActive(orbit: Orbit): Promise<void> {
    return run(
      orbit,
      () => orbitsService.update(orbit.id, { active: !orbit.active }),
      orbit.active ? `Orbit "${orbit.name}" desativado.` : `Orbit "${orbit.name}" ativado.`,
      'Falha ao alterar o Orbit',
    );
  }

  async function remove(orbit: Orbit): Promise<void> {
    const confirmed = await confirmDialog({
      title: 'Excluir Orbit',
      message: `Excluir o Orbit "${orbit.name}"? Os apps deixam de reconhecê-lo; o histórico de encontros é mantido.`,
      confirmLabel: 'Excluir',
      danger: true,
    });
    if (!confirmed) return;
    await run(orbit, () => orbitsService.remove(orbit.id), `Orbit "${orbit.name}" excluído.`, 'Falha ao excluir o Orbit');
  }

  void load();

  return {
    orbits, loaded, busyId, creating, form, editingId, draft, error, success,
    load, create, startEdit, cancelEdit, saveEdit, toggleActive, remove,
  };
}
