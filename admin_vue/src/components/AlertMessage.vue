<script setup lang="ts">
defineProps<{ message?: string | null }>();
</script>

<template>
  <div v-if="message" class="login-error" role="alert">{{ message }}</div>
</template>
