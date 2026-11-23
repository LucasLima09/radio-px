<script setup lang="ts">
import { computed } from 'vue';

import logoUrl from '../../../assets/images/logoktm.png';

import NavItem from './NavItem.vue';
import { adminPages } from '@/router/routes';
import { useAuthStore } from '@/stores/auth.store';
import { initial } from '@/utils/format';

defineProps<{ open: boolean }>();

const auth = useAuthStore();
const username = computed(() => auth.user?.username);
</script>

<template>
  <aside class="sidebar" :class="{ 'is-open': open }">
    <div class="sidebar-brand">
      <div class="brand-logo"><img :src="logoUrl" alt="KTM Indústria" /></div>
      <span>Radio PX · Central de administração</span>
    </div>
    <div class="nav-caption">WORKSPACE</div>
    <nav class="sidebar-nav" aria-label="Navegação principal">
      <NavItem v-for="page in adminPages" :key="page.name" :page="page" />
    </nav>
    <div class="sidebar-note">
      <span class="status-dot" /> Monitoramento de posições
      <p>Acompanhe a operação e gerencie os acessos em um só lugar.</p>
    </div>
    <div class="sidebar-footer">
      <span class="avatar">{{ initial(username, 'A') }}</span>
      <div class="account"><strong>{{ username ?? 'admin' }}</strong><small>Administrador</small></div>
      <button class="danger" aria-label="Sair da conta" @click="auth.logout()">Sair</button>
    </div>
  </aside>
</template>
