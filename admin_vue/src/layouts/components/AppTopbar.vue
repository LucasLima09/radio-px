<script setup lang="ts">
import { computed } from 'vue';

import { useThemeStore } from '@/stores/theme.store';

defineProps<{ pageLabel: string; menuOpen: boolean }>();
defineEmits<{ 'toggle-menu': [] }>();

const theme = useThemeStore();
const isDark = computed(() => theme.theme === 'dark');
</script>

<template>
  <header class="topbar">
    <button class="menu-toggle" aria-label="Abrir navegação" :aria-expanded="menuOpen" @click="$emit('toggle-menu')">☰</button>
    <span>Administração <span class="breadcrumb-divider">/</span> <strong>{{ pageLabel }}</strong></span>
    <div class="topbar-actions">
      <span class="workspace-badge">RADIO PX · ADMIN</span>
      <button
        class="theme-toggle"
        :aria-label="isDark ? 'Ativar modo claro' : 'Ativar modo escuro'"
        :title="isDark ? 'Modo claro' : 'Modo escuro'"
        @click="theme.toggle()"
      >
        {{ isDark ? '☀' : '☾' }}
      </button>
    </div>
  </header>
</template>
