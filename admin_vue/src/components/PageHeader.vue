<script setup lang="ts">
defineProps<{
  title: string;
  meta?: string;
  error?: string | null;
  success?: string | null;
}>();
</script>

<template>
  <div class="page-header">
    <h2>{{ title }}</h2>
    <span v-if="meta" class="meta">{{ meta }}</span>
    <span v-if="error" class="error">{{ error }}</span>
    <span v-if="success" class="success">{{ success }}</span>
    <slot />
  </div>
</template>
