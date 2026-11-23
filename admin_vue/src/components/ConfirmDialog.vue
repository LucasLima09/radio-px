<script setup lang="ts">
import { nextTick, ref, watch } from 'vue';

import { useConfirmState } from '@/composables/useConfirm';

const { state, accept, cancel } = useConfirmState();
const cancelBtn = ref<HTMLButtonElement | null>(null);

watch(
  () => state.open,
  async (open) => {
    if (!open) return;
    await nextTick();
    cancelBtn.value?.focus();
  },
);
</script>

<template>
  <Teleport to="body">
    <div v-if="state.open" class="confirm-backdrop" @click.self="cancel" @keydown.esc="cancel">
      <div class="confirm-dialog" role="alertdialog" aria-modal="true" aria-labelledby="confirm-title" aria-describedby="confirm-message">
        <h2 id="confirm-title">{{ state.title }}</h2>
        <p id="confirm-message">{{ state.message }}</p>
        <div class="confirm-actions">
          <button ref="cancelBtn" type="button" class="ghost" @click="cancel">{{ state.cancelLabel }}</button>
          <button type="button" :class="state.danger ? 'danger-solid' : 'primary'" @click="accept">
            {{ state.confirmLabel }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
