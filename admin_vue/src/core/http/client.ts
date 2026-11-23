import { errorFrom } from './errors';

/** Ponte entre o client e quem guarda a sessão (auth store). */
export interface AuthBridge {
  baseUrl(): string;
  accessToken(): string | null;
  /** Renova os tokens; retorna false se a sessão não puder ser renovada. */
  refresh(): Promise<boolean>;
  /** Chamado quando a API recusa a sessão (401/403) mesmo após o refresh. */
  onUnauthorized(): void;
}

export interface RequestOptions extends Omit<RequestInit, 'body'> {
  body?: unknown;
  /** Envia o Bearer token (padrão: true). */
  auth?: boolean;
  /** Tenta refresh + repetição em 401 e notifica a sessão expirada (padrão: igual a `auth`). */
  handleUnauthorized?: boolean;
}

const noBridge: AuthBridge = {
  baseUrl: () => '',
  accessToken: () => null,
  refresh: async () => false,
  onUnauthorized: () => {},
};

export class HttpClient {
  private bridge: AuthBridge = noBridge;
  private refreshing: Promise<boolean> | null = null;

  setAuthBridge(bridge: AuthBridge): void {
    this.bridge = bridge;
  }

  get<T>(path: string, options?: RequestOptions): Promise<T> {
    return this.request<T>(path, { ...options, method: 'GET' });
  }

  post<T>(path: string, body?: unknown, options?: RequestOptions): Promise<T> {
    return this.request<T>(path, { ...options, method: 'POST', body });
  }

  patch<T>(path: string, body?: unknown, options?: RequestOptions): Promise<T> {
    return this.request<T>(path, { ...options, method: 'PATCH', body });
  }

  delete<T = void>(path: string, options?: RequestOptions): Promise<T> {
    return this.request<T>(path, { ...options, method: 'DELETE' });
  }

  async request<T>(path: string, options: RequestOptions = {}): Promise<T> {
    const { body, auth = true, handleUnauthorized = auth, headers, ...init } = options;

    const doFetch = () =>
      fetch(this.bridge.baseUrl() + path, {
        ...init,
        headers: { ...this.headers(auth), ...(headers as Record<string, string>) },
        body: body === undefined ? undefined : JSON.stringify(body),
      });

    let res = await doFetch();
    if (handleUnauthorized && res.status === 401 && (await this.refreshOnce())) {
      res = await doFetch();
    }
    if (!res.ok) {
      if (handleUnauthorized && (res.status === 401 || res.status === 403)) {
        this.bridge.onUnauthorized();
      }
      throw await errorFrom(res);
    }
    if (res.status === 204) return undefined as T;
    return (await res.json()) as T;
  }

  private headers(auth: boolean): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': '1',
    };
    const token = auth ? this.bridge.accessToken() : null;
    if (token) headers['Authorization'] = `Bearer ${token}`;
    return headers;
  }

  // Várias requisições podem receber 401 juntas (polling): um único refresh atende todas.
  private refreshOnce(): Promise<boolean> {
    this.refreshing ??= this.bridge.refresh().finally(() => {
      this.refreshing = null;
    });
    return this.refreshing;
  }
}

export const http = new HttpClient();
