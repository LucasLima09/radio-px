<script setup lang="ts">
export interface Column {
  label: string;
  class?: string;
}

defineProps<{
  columns: Column[];
  /** Mensagem da linha vazia; omitida, a linha não aparece. */
  emptyText?: string | null;
}>();
</script>

<template>
  <div class="table-wrap">
    <table class="data-table">
      <thead>
        <tr>
          <th v-for="col in columns" :key="col.label" :class="col.class">{{ col.label }}</th>
        </tr>
      </thead>
      <tbody>
        <slot />
        <tr v-if="emptyText">
          <td :colspan="columns.length" class="muted center">{{ emptyText }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
