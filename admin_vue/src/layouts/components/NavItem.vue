<script setup lang="ts">
import type { AdminPage } from '@/router/routes';

defineProps<{ page: AdminPage }>();
</script>

<template>
  <!-- <button> (e não <a>) para reaproveitar os estilos de .sidebar-nav button. -->
  <RouterLink v-slot="{ navigate, isActive }" :to="{ name: page.name }" custom>
    <button :class="{ active: isActive }" :aria-current="isActive ? 'page' : undefined" @click="navigate">
      <span class="nav-icon" aria-hidden="true">{{ page.icon }}</span>
      <span><strong>{{ page.label }}</strong><small>{{ page.detail }}</small></span>
      <span class="nav-arrow" aria-hidden="true">›</span>
    </button>
  </RouterLink>
</template>
