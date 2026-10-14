import { useCallback, useEffect, useRef, useState } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

import { Api, ApiError, type LocationReport, type PublicUser } from './api';

const DEFAULT_SERVER = 'http://localhost:8080';
const SERVER_KEY = 'radio_px_admin_server';
const POLL_INTERVAL_MS = 5000;

type Page = 'map' | 'users' | 'log';

export default function App() {
  const [server, setServer] = useState(
    () => localStorage.getItem(SERVER_KEY) ?? DEFAULT_SERVER,
  );
  const [api, setApi] = useState(
    () => new Api(localStorage.getItem(SERVER_KEY) ?? DEFAULT_SERVER),
  );
  const [loggedIn, setLoggedIn] = useState<boolean>(api.hasSession);
  const [page, setPage] = useState<Page>('map');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const handleLogin = async (username: string, password: string) => {
    setBusy(true);
    setError(null);
    const normalized = server.trim().replace(/\/+$/, '') || DEFAULT_SERVER;
    try {
      const next = new Api(normalized);
      await next.login(username, password);
      localStorage.setItem(SERVER_KEY, normalized);
      setServer(normalized);
      setApi(next);
      setPage('map');
      setLoggedIn(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Falha ao entrar');
    } finally {
      setBusy(false);
    }
  };

  const handleLogout = async () => {
    await api.logout();
    setLoggedIn(false);
  };

  const goLogin = useCallback(() => setLoggedIn(false), []);

  return !loggedIn ? (
    <LoginView
      server={server}
      onServer={setServer}
      onLogin={handleLogin}
      busy={busy}
      error={error}
    />
  ) : (
    <Dashboard
      api={api}
      page={page}
      onPage={setPage}
      onLogout={handleLogout}
      onUnauthorized={goLogin}
    />
  );
}

function LoginView({
  server,
  onServer,
  onLogin,
  busy,
  error,
}: {
  server: string;
  onServer: (v: string) => void;
  onLogin: (username: string, password: string) => void;
  busy: boolean;
  error: string | null;
}) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

  const submit = () => {
    if (!username.trim() || !password || busy) return;
    onLogin(username.trim(), password);
  };

  return (
    <div className="login-shell">
      <div className="login-card">
        <h1>Radio PX · Admin</h1>
        <p className="subtitle">Acesso restrito · relatório de posição</p>
        {error && <div className="login-error">{error}</div>}
        <label>
          Servidor
          <input
            value={server}
            onChange={(e) => onServer(e.target.value)}
            placeholder={DEFAULT_SERVER}
          />
        </label>
        <label>
          Usuário
          <input
            autoComplete="username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
          />
        </label>
        <label>
          Senha
          <input
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') submit();
            }}
          />
        </label>
        <button disabled={busy} onClick={submit}>
          {busy ? 'Entrando...' : 'Entrar'}
        </button>
      </div>
    </div>
  );
}

function Dashboard({
  api,
  page,
  onPage,
  onLogout,
  onUnauthorized,
}: {
  api: Api;
  page: Page;
  onPage: (p: Page) => void;
  onLogout: () => void;
  onUnauthorized: () => void;
}) {
  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="sidebar-brand">
          <h1>Radio PX</h1>
          <span>Painel admin</span>
        </div>
        <nav className="sidebar-nav">
          <button
            className={page === 'map' ? 'active' : ''}
            onClick={() => onPage('map')}
          >
            Mapa
          </button>
          <button
            className={page === 'users' ? 'active' : ''}
            onClick={() => onPage('users')}
          >
            Usuários
          </button>
          <button
            className={page === 'log' ? 'active' : ''}
            onClick={() => onPage('log')}
          >
            Log de posições
          </button>
        </nav>
        <div className="sidebar-footer">
          <span className="who">{api.user?.username ?? 'admin'}</span>
          <button onClick={onLogout}>Sair</button>
        </div>
      </aside>
      <main className="main">
        {page === 'map' && (
          <MapPage api={api} onUnauthorized={onUnauthorized} />
        )}
        {page === 'users' && (
          <UsersPage api={api} onUnauthorized={onUnauthorized} />
        )}
        {page === 'log' && (
          <LogPage api={api} onUnauthorized={onUnauthorized} />
        )}
      </main>
    </div>
  );
}

function unauthorizedMessage(e: unknown) {
  return e instanceof ApiError && (e.status === 401 || e.status === 403);
}

function MapPage({
  api,
  onUnauthorized,
}: {
  api: Api;
  onUnauthorized: () => void;
}) {
  const [reports, setReports] = useState<LocationReport[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      try {
        const data = await api.latestLocations();
        if (cancelled) return;
        setReports(data);
        setError(null);
      } catch (e) {
        if (cancelled) return;
        if (unauthorizedMessage(e)) {
          setError('Sessão expirada ou sem permissão de admin.');
          onUnauthorized();
          return;
        }
        setError(e instanceof Error ? e.message : 'Falha ao buscar as posições');
      }
    };

    load();
    const id = setInterval(load, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [api, onUnauthorized]);

  return (
    <div className="page">
      <div className="page-header">
        <h2>Mapa ao vivo</h2>
        <span className="meta">
          {reports.length} posição(ões) · atualiza a cada {POLL_INTERVAL_MS / 1000}s
        </span>
        {error && <span className="error">{error}</span>}
      </div>
      <div className="map-container">
        <MapView reports={reports} />
      </div>
    </div>
  );
}

function MapView({ reports }: { reports: LocationReport[] }) {
  const elRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const markersRef = useRef<L.Marker[]>([]);
  const fittedRef = useRef<string>('');

  useEffect(() => {
    const el = elRef.current;
    if (!el) return;
    const map = L.map(el).setView([-23.5505, -46.6333], 5);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap',
    }).addTo(map);
    mapRef.current = map;
    return () => {
      map.remove();
      mapRef.current = null;
      markersRef.current = [];
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    for (const marker of markersRef.current) {
      marker.remove();
    }
    markersRef.current = reports.map((r) => {
      const marker = L.marker([r.lat, r.lng], {
        icon: L.divIcon({
          className: 'beacon-marker',
          html: `<div class="beacon-marker__pin">${
            r.username ? r.username[0].toUpperCase() : '?'
          }</div>`,
          iconSize: [32, 32],
          iconAnchor: [16, 16],
        }),
      });
      marker.bindPopup(
        `<b>${r.username}</b><br/>${r.lat.toFixed(5)}, ${r.lng.toFixed(
          5,
        )}<br/>${new Date(r.reportedAt).toLocaleString()}`,
      );
      marker.addTo(map);
      return marker;
    });

    const ids = reports.map((r) => r.userId).join('|');
    if (reports.length > 0 && ids !== fittedRef.current) {
      fittedRef.current = ids;
      if (reports.length === 1) {
        map.setView([reports[0].lat, reports[0].lng], 14);
      } else {
        map.fitBounds(
          L.latLngBounds(reports.map((r) => [r.lat, r.lng] as [number, number])),
          { padding: [48, 48] },
        );
      }
    }
  }, [reports]);

  return <div className="leaflet-container" ref={elRef} />;
}

function UsersPage({
  api,
  onUnauthorized,
}: {
  api: Api;
  onUnauthorized: () => void;
}) {
  const [users, setUsers] = useState<PublicUser[]>([]);
  const [drafts, setDrafts] = useState<Record<string, PublicUser>>({});
  const [savingId, setSavingId] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);

  const load = useCallback(async () => {
    try {
      const data = await api.listUsers();
      setUsers(data);
      setDrafts({});
      setError(null);
      setLoaded(true);
    } catch (e) {
      if (unauthorizedMessage(e)) {
        onUnauthorized();
        return;
      }
      setError(e instanceof Error ? e.message : 'Falha ao listar usuários');
    }
  }, [api, onUnauthorized]);

  useEffect(() => {
    load();
  }, [load]);

  const setDraft = (u: PublicUser, patch: Partial<PublicUser>) => {
    setDrafts((prev) => ({ ...prev, [u.id]: { ...prev[u.id], ...patch } }));
  };
  const resetDraft = (u: PublicUser) => {
    setDrafts((prev) => {
      const next = { ...prev };
      delete next[u.id];
      return next;
    });
  };

  const save = async (u: PublicUser) => {
    const draft = drafts[u.id];
    if (!draft) return;
    setSavingId(u.id);
    setError(null);
    setSuccess(null);
    try {
      const updated = await api.updateUser(u.id, {
        username: draft.username,
        role: draft.role,
      });
      setUsers((prev) =>
        prev.map((x) => (x.id === u.id ? { ...x, ...updated } : x)),
      );
      resetDraft(u);
      setSuccess(`Usuário "${updated.username}" atualizado.`);
    } catch (e) {
      if (unauthorizedMessage(e)) {
        onUnauthorized();
        return;
      }
      setError(e instanceof Error ? e.message : 'Falha ao salvar');
    } finally {
      setSavingId(null);
    }
  };

  const remove = async (u: PublicUser) => {
    if (
      !window.confirm(
        `Excluir o usuário "${u.username}"? Isso remove também os canais, posições e tokens dele. Esta ação não pode ser desfeita.`,
      )
    ) {
      return;
    }
    setDeletingId(u.id);
    setError(null);
    setSuccess(null);
    try {
      await api.deleteUser(u.id);
      setUsers((prev) => prev.filter((x) => x.id !== u.id));
      resetDraft(u);
      setSuccess(`Usuário "${u.username}" excluído.`);
    } catch (e) {
      if (unauthorizedMessage(e)) {
        onUnauthorized();
        return;
      }
      setError(e instanceof Error ? e.message : 'Falha ao excluir');
    } finally {
      setDeletingId(null);
    }
  };

  return (
    <div className="page">
      <div className="page-header">
        <h2>Usuários</h2>
        <span className="meta">
          {users.length} cadastrado(s)
          {!loaded && ' · carregando...'}
        </span>
        {error && <span className="error">{error}</span>}
        {success && <span className="success">{success}</span>}
        <button className="ghost" onClick={load}>
          Atualizar
        </button>
      </div>

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Usuário</th>
              <th>Role</th>
              <th>Criado em</th>
              <th className="actions-col">Ações</th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => {
              const draft = drafts[u.id];
              const dirty =
                draft !== undefined &&
                (draft.username !== u.username ||
                  (draft.role ?? u.role) !== (u.role ?? 'user'));
              return (
                <tr key={u.id}>
                  <td>
                    <input
                      className="inline-input"
                      value={draft?.username ?? u.username}
                      onChange={(e) =>
                        setDraft(u, { username: e.target.value })
                      }
                    />
                  </td>
                  <td>
                    <select
                      className="inline-select"
                      value={draft?.role ?? u.role ?? 'user'}
                      onChange={(e) => setDraft(u, { role: e.target.value })}
                    >
                      <option value="user">user</option>
                      <option value="admin">admin</option>
                    </select>
                  </td>
                  <td className="muted">
                    {u.createdAt
                      ? new Date(u.createdAt).toLocaleString()
                      : '—'}
                  </td>
                  <td className="actions-col">
                    <div className="inline-actions">
                      {dirty && (
                        <button
                          className="primary"
                          disabled={savingId != null || deletingId != null}
                          onClick={() => save(u)}
                        >
                          {savingId === u.id ? 'Salvando...' : 'Salvar'}
                        </button>
                      )}
                      {draft && (
                        <button
                          className="ghost"
                          disabled={savingId != null || deletingId != null}
                          onClick={() => resetDraft(u)}
                        >
                          Cancelar
                        </button>
                      )}
                      <button
                        className="danger"
                        disabled={
                          savingId != null ||
                          deletingId != null ||
                          u.id === api.user?.id
                        }
                        title={
                          u.id === api.user?.id
                            ? 'Você não pode excluir sua própria conta'
                            : 'Excluir usuário'
                        }
                        onClick={() => remove(u)}
                      >
                        {deletingId === u.id ? 'Excluindo...' : 'Excluir'}
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })}
            {users.length === 0 && !error && (
              <tr>
                <td colSpan={4} className="muted center">
                  Nenhum usuário cadastrado.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function LogPage({
  api,
  onUnauthorized,
}: {
  api: Api;
  onUnauthorized: () => void;
}) {
  const [history, setHistory] = useState<LocationReport[]>([]);
  const [users, setUsers] = useState<PublicUser[]>([]);
  const [filterUserId, setFilterUserId] = useState<string>('');
  const [limit, setLimit] = useState(200);
  const [error, setError] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const [log, allUsers] = await Promise.all([
        api.locationHistory(filterUserId || undefined, limit),
        api.listUsers(),
      ]);
      setHistory(log);
      setUsers(allUsers);
      setError(null);
      setLoaded(true);
    } catch (e) {
      if (unauthorizedMessage(e)) {
        onUnauthorized();
        return;
      }
      setError(e instanceof Error ? e.message : 'Falha ao carregar o log');
    }
  }, [api, filterUserId, limit, onUnauthorized]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return (
    <div className="page">
      <div className="page-header">
        <h2>Log de posições</h2>
        <span className="meta">
          {history.length} registro(s)
          {!loaded && ' · carregando...'}
        </span>
        {error && <span className="error">{error}</span>}
      </div>

      <div className="filters">
        <label>
          Motorista
          <select
            value={filterUserId}
            onChange={(e) => setFilterUserId(e.target.value)}
          >
            <option value="">Todos</option>
            {users.map((u) => (
              <option key={u.id} value={u.id}>
                {u.username}
              </option>
            ))}
          </select>
        </label>
        <label>
          Máximo
          <select
            value={limit}
            onChange={(e) => setLimit(Number(e.target.value))}
          >
            <option value={100}>100</option>
            <option value={200}>200</option>
            <option value={500}>500</option>
            <option value={1000}>1000</option>
          </select>
        </label>
        <button className="ghost" onClick={refresh}>
          Recarregar
        </button>
      </div>

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Motorista</th>
              <th>Latitude</th>
              <th>Longitude</th>
              <th>Horário</th>
            </tr>
          </thead>
          <tbody>
            {history.map((r, i) => (
              <tr key={`${r.userId}-${r.reportedAt}-${i}`}>
                <td className="cell-user">{r.username}</td>
                <td className="mono">{r.lat.toFixed(6)}</td>
                <td className="mono">{r.lng.toFixed(6)}</td>
                <td className="muted">
                  {new Date(r.reportedAt).toLocaleString()}
                </td>
              </tr>
            ))}
            {history.length === 0 && !error && (
              <tr>
                <td colSpan={4} className="muted center">
                  {loaded
                    ? 'Nenhuma posição registrada.'
                    : 'Carregando...'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}