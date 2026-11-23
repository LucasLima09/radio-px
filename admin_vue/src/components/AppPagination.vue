<script setup lang="ts">
const props = defineProps<{ page: number; totalPages: number }>();
const emit = defineEmits<{ 'update:page': [page: number] }>();

function go(page: number): void {
  emit('update:page', Math.min(props.totalPages, Math.max(1, page)));
}
</script>

<template>
  <div class="pagination">
    <button class="ghost" :disabled="page <= 1" @click="go(page - 1)">‹ Anterior</button>
    <span class="muted">Página {{ page }} de {{ totalPages }}</span>
    <button class="ghost" :disabled="page >= totalPages" @click="go(page + 1)">Próxima ›</button>
  </div>
</template>
