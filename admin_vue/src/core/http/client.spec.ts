import { afterEach, describe, expect, it, vi } from 'vitest';

import { HttpClient, type AuthBridge } from './client';
import { ApiError } from './errors';

function json(status: number, body?: unknown): Response {
  return new Response(body === undefined ? null : JSON.stringify(body), { status });
}

function setup(responses: Response[], bridge: Partial<AuthBridge> = {}) {
  const fetchMock = vi.fn(async () => responses.shift()!);
  vi.stubGlobal('fetch', fetchMock);
  const full: AuthBridge = {
    baseUrl: () => 'http://api',
    accessToken: () => 'token',
    refresh: vi.fn(async () => true),
    onUnauthorized: vi.fn(),
    ...bridge,
  };
  const client = new HttpClient();
  client.setAuthBridge(full);
  return { client, fetchMock, bridge: full };
}

afterEach(() => vi.unstubAllGlobals());

describe('HttpClient', () => {
  it('envia o Bearer token e decodifica o JSON', async () => {
    const { client, fetchMock } = setup([json(200, { ok: true })]);
    await expect(client.get('/x')).resolves.toEqual({ ok: true });
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('http://api/x');
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer token');
  });

  it('renova a sessão no 401 e repete a requisição', async () => {
    const { client, fetchMock, bridge } = setup([json(401), json(200, [1])]);
    await expect(client.get('/x')).resolves.toEqual([1]);
    expect(bridge.refresh).toHaveBeenCalledOnce();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('notifica sessão expirada quando o refresh falha', async () => {
    const { client, bridge } = setup([json(401, { error: 'expirado' })], { refresh: vi.fn(async () => false) });
    await expect(client.get('/x')).rejects.toEqual(new ApiError(401, 'expirado'));
    expect(bridge.onUnauthorized).toHaveBeenCalledOnce();
  });

  it('notifica 403 sem tentar refresh', async () => {
    const { client, bridge } = setup([json(403)]);
    await expect(client.get('/x')).rejects.toMatchObject({ status: 403, message: 'Erro 403' });
    expect(bridge.refresh).not.toHaveBeenCalled();
    expect(bridge.onUnauthorized).toHaveBeenCalledOnce();
  });

  it('não envia token nem trata 401 em requisições sem auth', async () => {
    const { client, fetchMock, bridge } = setup([json(401)]);
    await expect(client.post('/login', {}, { auth: false })).rejects.toBeInstanceOf(ApiError);
    const init = fetchMock.mock.calls[0][1 as never] as RequestInit;
    expect((init.headers as Record<string, string>).Authorization).toBeUndefined();
    expect(bridge.refresh).not.toHaveBeenCalled();
    expect(bridge.onUnauthorized).not.toHaveBeenCalled();
  });

  it('faz um único refresh para 401 simultâneos', async () => {
    let resolveRefresh!: (ok: boolean) => void;
    const refresh = vi.fn(() => new Promise<boolean>((r) => (resolveRefresh = r)));
    const { client } = setup([json(401), json(401), json(200, 1), json(200, 2)], { refresh });
    const both = Promise.all([client.get('/a'), client.get('/b')]);
    await vi.waitFor(() => expect(refresh).toHaveBeenCalled());
    resolveRefresh(true);
    await expect(both).resolves.toEqual([1, 2]);
    expect(refresh).toHaveBeenCalledOnce();
  });

  it('retorna undefined em 204', async () => {
    const { client } = setup([new Response(null, { status: 204 })]);
    await expect(client.delete('/x')).resolves.toBeUndefined();
  });
});
