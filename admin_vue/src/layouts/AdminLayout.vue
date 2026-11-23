<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';

import AppSidebar from './components/AppSidebar.vue';
import AppTopbar from './components/AppTopbar.vue';

const route = useRoute();
const menuOpen = ref(false);
const pageLabel = computed(() => route.meta.label ?? '');

// Fecha o menu mobile ao navegar.
watch(() => route.name, () => {
  menuOpen.value = false;
});
</script>

<template>
  <div class="shell">
    <button v-if="menuOpen" class="menu-overlay" aria-label="Fechar navegação" @click="menuOpen = false" />
    <AppSidebar :open="menuOpen" />
    <main class="main">
      <AppTopbar :page-label="pageLabel" :menu-open="menuOpen" @toggle-menu="menuOpen = !menuOpen" />
      <RouterView />
    </main>
  </div>
</template>
