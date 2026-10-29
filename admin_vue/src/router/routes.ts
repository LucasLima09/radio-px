import type { RouteRecordRaw } from 'vue-router';

import AdminLayout from '@/layouts/AdminLayout.vue';
import LoginView from '@/features/auth/LoginView.vue';

export interface AdminPage {
  name: string;
  path: string;
  label: string;
  detail: string;
  icon: string;
  component: RouteRecordRaw['component'];
}

/** Páginas do painel: fonte única para rotas, sidebar e breadcrumb. */
export const adminPages: AdminPage[] = [
  { name: 'overview', path: 'overview', label: 'Visão geral', detail: 'Resumo da operação', icon: '◫', component: () => import('@/features/overview/OverviewView.vue') },
  { name: 'map', path: 'map', label: 'Mapa ao vivo', detail: 'Localização dos motoristas', icon: '◎', component: () => import('@/features/map/LiveMapView.vue') },
  { name: 'users', path: 'users', label: 'Usuários', detail: 'Contas e permissões', icon: '♙', component: () => import('@/features/users/UsersView.vue') },
  { name: 'channels', path: 'channels', label: 'Canais', detail: 'Canais e pessoas online', icon: '#', component: () => import('@/features/channels/ChannelsView.vue') },
  { name: 'log', path: 'log', label: 'Histórico de posições', detail: 'Registros e consultas', icon: '≡', component: () => import('@/features/location-log/LocationLogView.vue') },
];

declare module 'vue-router' {
  interface RouteMeta {
    public?: boolean;
    label?: string;
  }
}

export const routes: RouteRecordRaw[] = [
  { path: '/login', name: 'login', component: LoginView, meta: { public: true } },
  {
    path: '/',
    component: AdminLayout,
    redirect: { name: 'overview' },
    children: adminPages.map(({ name, path, label, component }) => ({
      name,
      path,
      component: component!,
      meta: { label },
    })),
  },
  { path: '/:pathMatch(.*)*', redirect: '/' },
];
