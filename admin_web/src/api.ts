export interface PublicUser {
  id: string;
  username: string;
  role?: string;
  createdAt?: string;
}

export interface AuthSession {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  user: PublicUser;
}

export interface LocationReport {
  userId: string;
  username: string;
  lat: number;
  lng: number;
  reportedAt: string;
}

export interface AdminChannel {
  id: string;
  name: string;
  owner: string;
  online: number;
  members?: number;
  isPrivate: boolean;
  createdAt?: string;
}

export interface Page<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

const AUTH_KEY = 'radio_px_admin_auth';

export class Api {
  private accessToken: string | null = null;
  private refreshToken: string | null = null;
  user: PublicUser | null = null;

  constructor(public baseUrl: string) {
    const saved = localStorage.getItem(AUTH_KEY);
    if (!saved) return;
    try {
      const session = JSON.parse(saved) as AuthSession;
      this.accessToken = session.accessToken;
      this.refreshToken = session.refreshToken;
      this.user = session.user;
    } catch {
      localStorage.removeItem(AUTH_KEY);
    }
  }

  get hasSession(): boolean {
    return this.accessToken != null;
  }

  private url(path: string): string {
    const base = this.baseUrl.trim().replace(/\/+$/, '');
    return base + path;
  }

  private headers(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': '1',
    };
    if (this.accessToken) {
      headers['Authorization'] = `Bearer ${this.accessToken}`;
    }
    return headers;
  }

  async login(username: string, password: string): Promise<void> {
    const res = await fetch(this.url('/api/v1/auth/login'), {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify({ username, password }),
    });
    if (!res.ok) throw await this.errorFrom(res);
    const session = (await res.json()) as AuthSession;
    this.applySession(session);
  }

  async refresh(): Promise<boolean> {
    if (!this.refreshToken) return false;
    const res = await fetch(this.url('/api/v1/auth/refresh'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken: this.refreshToken }),
    });
    if (!res.ok) {
      this.clearSession();
      return false;
    }
    this.applySession((await res.json()) as AuthSession);
    return true;
  }

  async latestLocations(): Promise<LocationReport[]> {
    return this.request('/api/v1/admin/locations');
  }

  async locationHistory(userId?: string, limit = 200): Promise<LocationReport[]> {
    const params = new URLSearchParams();
    if (userId) params.set('userId', userId);
    params.set('limit', String(limit));
    return this.request(`/api/v1/admin/locations/history?${params.toString()}`);
  }

  async listUsers(): Promise<PublicUser[]> {
    return this.request('/api/v1/admin/users');
  }

  async updateUser(
    id: string,
    patch: { username?: string; role?: string },
  ): Promise<PublicUser> {
    return this.request(`/api/v1/admin/users/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(patch),
    });
  }

  async deleteUser(id: string): Promise<void> {
    await this.request(`/api/v1/admin/users/${id}`, { method: 'DELETE' });
  }

  async listChannels(search = '', page = 1): Promise<Page<AdminChannel>> {
    const params = new URLSearchParams();
    if (search) params.set('q', search);
    params.set('page', String(page));
    return this.request(`/api/v1/admin/channels?${params.toString()}`);
  }

  async deleteChannel(id: string): Promise<void> {
    await this.request(`/api/v1/admin/channels/${id}`, { method: 'DELETE' });
  }

  async logout(): Promise<void> {
    await fetch(this.url('/api/v1/auth/logout'), {
      method: 'POST',
      headers: this.headers(),
    }).catch(() => {});
    this.clearSession();
  }

  private async request<T>(path: string, init?: RequestInit): Promise<T> {
    const doFetch = () =>
      fetch(this.url(path), {
        ...init,
        headers: { ...this.headers(), ...(init?.headers ?? {}) },
      });

    let res = await doFetch();
    if (res.status === 401 && (await this.refresh())) {
      res = await doFetch();
    }
    if (!res.ok) throw await this.errorFrom(res);
    if (res.status === 204) return undefined as T;
    return (await res.json()) as T;
  }

  private applySession(session: AuthSession): void {
    this.accessToken = session.accessToken;
    this.refreshToken = session.refreshToken;
    this.user = session.user;
    localStorage.setItem(AUTH_KEY, JSON.stringify(session));
  }

  private clearSession(): void {
    this.accessToken = null;
    this.refreshToken = null;
    this.user = null;
    localStorage.removeItem(AUTH_KEY);
  }

  private async errorFrom(res: Response): Promise<ApiError> {
    let message = `Erro ${res.status}`;
    try {
      const body = (await res.json()) as { error?: string };
      if (body.error) message = body.error;
    } catch {
      // corpo não é JSON
    }
    return new ApiError(res.status, message);
  }
}