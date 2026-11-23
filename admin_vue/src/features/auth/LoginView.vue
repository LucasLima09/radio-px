<script setup lang="ts">
import { ref } from 'vue';
import { useRouter } from 'vue-router';

import logoUrl from '../../../assets/images/logoktm.png';

import AlertMessage from '@/components/AlertMessage.vue';
import { errorMessage } from '@/core/http/errors';
import { useAuthStore } from '@/stores/auth.store';

const auth = useAuthStore();
const router = useRouter();

const username = ref('');
const password = ref('');
const busy = ref(false);
const error = ref<string | null>(null);

async function submit(): Promise<void> {
  if (!username.value.trim() || !password.value || busy.value) return;
  busy.value = true;
  error.value = null;
  try {
    await auth.login(username.value.trim(), password.value);
    await router.push({ name: 'overview' });
  } catch (e) {
    error.value = errorMessage(e, 'Falha ao entrar');
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="login-shell">
    <img class="login-logo" :src="logoUrl" alt="KTM Indústria" />
    <div class="login-card">
      <h1>Radio PX · Admin</h1>
      <p class="subtitle">Acesso restrito · relatório de posição</p>
      <AlertMessage :message="error" />
      <label>
        Usuário
        <input v-model="username" autocomplete="username" autofocus />
      </label>
      <label>
        Senha
        <input v-model="password" type="password" autocomplete="current-password" @keydown.enter="submit" />
      </label>
      <button :disabled="busy" @click="submit">{{ busy ? 'Entrando...' : 'Entrar' }}</button>
    </div>
  </div>
</template>
