import { http } from '@/core/http/client';
import type { AuthSession } from '@/types';

export const authService = {
  login(username: string, password: string): Promise<AuthSession> {
    return http.post('/api/v1/auth/login', { username, password }, { auth: false });
  },
  refresh(refreshToken: string): Promise<AuthSession> {
    return http.post('/api/v1/auth/refresh', { refreshToken }, { auth: false });
  },
  logout(): Promise<void> {
    return http.post('/api/v1/auth/logout', undefined, { handleUnauthorized: false });
  },
};
