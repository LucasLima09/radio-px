import { useCallback, useEffect, useRef, useState } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

import { Api, ApiError, type AdminChannel, type LocationReport, type Page as ApiPage, type PublicUser } from './api';
import { DemoApi } from './demo';
import { isLiveLocation } from './location-status';
import { useTheme } from './theme';

const DEV_SERVER = 'http://localhost:8080';
const SERVER_KEY = 'radio_px_admin_server';
const POLL_INTERVAL_MS = 5000;

// Em desenvolvimento (Vite em :5173) aponta para o backend local.
// Servido pelo backend Go em /admin, usa a mesma origem.
const IS_VITE_DEV =
  typeof window !== 'undefined' && window.location.port === '5173';
const SERVER_PLACEHOLDER = IS_VITE_DEV
  ? DEV_SERVER
  : typeof window !== 'undefined'
    ? window.location.origin
    : DEV_SERVER;

function initialServer(): string {
  if (!IS_VITE_DEV) return '';
  return localStorage.getItem(SERVER_KEY) ?? DEV_SERVER;
}

type Page = 'overview' | 'map' | 'users' | 'channels' | 'log';

export default function App() {
  const [server, setServer] = useState(initialServer);
  const [api, setApi] = useState(() => new Api(initialServer()));
  const [loggedIn, setLoggedIn] = useState<boolean>(api.hasSession);
  const [page, setPage] = useState<Page>('overview');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const handleLogin = async (username: string, password: string) => {
    setBusy(true);
    setError(null);
    const normalized = server.trim().replace(/\/+$/, '');
    try {
      const next = new Api(normalized);
      await next.login(username, password);
      localStorage.setItem(SERVER_KEY, normalized);
      setServer(normalized);
      setApi(next);
      setPage('overview');
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
      onDemo={() => { setApi(new DemoApi()); setPage('overview'); setError(null); setLoggedIn(true); }}
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
  onDemo,
  busy,
  error,
}: {
  server: string;
  onServer: (v: string) => void;
  onLogin: (username: string, password: string) => void;
  onDemo: () => void;
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
            placeholder={SERVER_PLACEHOLDER}
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
        <button className="demo-button" disabled={busy} onClick={onDemo}>Experimentar sem backend</button>
        <p className="demo-hint">Explore o painel com dados de exemplo, sem servidor ou senha.</p>
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
  const [menuOpen, setMenuOpen] = useState(false);
  const { theme, toggle } = useTheme();
  const items: { id: Page; label: string; detail: string; icon: string }[] = [
    { id: 'overview', label: 'Visão geral', detail: 'Resumo da operação', icon: '◫' },
    { id: 'map', label: 'Mapa ao vivo', detail: 'Localização dos motoristas', icon: '◎' },
    { id: 'users', label: 'Usuários', detail: 'Contas e permissões', icon: '♙' },
    { id: 'channels', label: 'Canais', detail: 'Canais e pessoas online', icon: '#' },
    { id: 'log', label: 'Histórico de posições', detail: 'Registros e consultas', icon: '≡' },
  ];
  const selected = items.find((item) => item.id === page)!;
  return (
    <div className="shell">
      {menuOpen && <button className="menu-overlay" aria-label="Fechar navegação" onClick={() => setMenuOpen(false)} />}
      <aside className={`sidebar ${menuOpen ? 'is-open' : ''}`}>
        <div className="sidebar-brand"><div className="brand-symbol">PX</div><div><h1>Radio PX</h1><span>Central de administração</span></div></div>
        <div className="nav-caption">WORKSPACE</div>
        <nav className="sidebar-nav" aria-label="Navegação principal">
          {items.map((item) => <button key={item.id} className={page === item.id ? 'active' : ''} aria-current={page === item.id ? 'page' : undefined} onClick={() => { onPage(item.id); setMenuOpen(false); }}><span className="nav-icon" aria-hidden="true">{item.icon}</span><span><strong>{item.label}</strong><small>{item.detail}</small></span><span className="nav-arrow" aria-hidden="true">›</span></button>)}
        </nav>
        <div className="sidebar-note"><span className="status-dot" /> Monitoramento de posições<p>Acompanhe a operação e gerencie os acessos em um só lugar.</p></div>
        <div className="sidebar-footer"><span className="avatar">{api.user?.username?.[0]?.toUpperCase() ?? 'A'}</span><div className="account"><strong>{api.user?.username ?? 'admin'}</strong><small>Administrador</small></div><button className="danger" onClick={onLogout} aria-label="Sair da conta">Sair</button></div>
      </aside>
      <main className="main">
        {api instanceof DemoApi && <div className="demo-banner">Modo demonstração · Dados fictícios. Alterações valem apenas nesta sessão.</div>}
        <header className="topbar"><button className="menu-toggle" aria-label="Abrir navegação" aria-expanded={menuOpen} onClick={() => setMenuOpen(!menuOpen)}>☰</button><span>Administração <span className="breadcrumb-divider">/</span> <strong>{selected.label}</strong></span><div className="topbar-actions"><span className="workspace-badge">RADIO PX · ADMIN</span><button className="theme-toggle" onClick={toggle} aria-label={theme === 'dark' ? 'Ativar modo claro' : 'Ativar modo escuro'} title={theme === 'dark' ? 'Modo claro' : 'Modo escuro'}>{theme === 'dark' ? '☀' : '☾'}</button></div></header>
        {page === 'overview' && <OverviewPage api={api} onUnauthorized={onUnauthorized} onPage={onPage} />}
        {page === 'map' && <MapPage api={api} onUnauthorized={onUnauthorized} />}
        {page === 'users' && <UsersPage api={api} onUnauthorized={onUnauthorized} />}
        {page === 'channels' && <ChannelsPage api={api} onUnauthorized={onUnauthorized} />}
        {page === 'log' && <LogPage api={api} onUnauthorized={onUnauthorized} />}
      </main>
    </div>
  );
}

function OverviewPage({ api, onUnauthorized, onPage }: { api: Api; onUnauthorized: () => void; onPage: (page: Page) => void }) {
  const [data, setData] = useState<{ users: PublicUser[]; locations: LocationReport[] } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [updated, setUpdated] = useState<Date | null>(null);
  useEffect(() => {
    let cancelled = false;
    let pending = false;
    const load = async () => {
      if (pending) return;
      pending = true;
      try {
        const [users, locations] = await Promise.all([api.listUsers(), api.latestLocations()]);
        if (!cancelled) { setData({ users, locations }); setUpdated(new Date()); setError(null); }
      } catch (e) {
        if (!cancelled) {
          if (unauthorizedMessage(e)) onUnauthorized();
          else setError(e instanceof Error ? e.message : 'Falha ao carregar o resumo');
        }
      } finally { pending = false; }
    };
    void load();
    const timer = setInterval(load, POLL_INTERVAL_MS);
    return () => { cancelled = true; clearInterval(timer); };
  }, [api, onUnauthorized]);
  return <div className="page overview-page">
    <div className="overview-heading"><div><span className="eyebrow">CENTRAL DE OPERAÇÕES</span><h2>Visão geral</h2><p>Uma visão clara de quem está na estrada.</p></div><span className="update-label">{updated ? `Atualizado às ${updated.toLocaleTimeString('pt-BR')}` : 'Carregando indicadores…'}</span></div>
    {error && <div className="login-error" role="alert">{error}</div>}
    <div className="stats-grid">
      {[['Usuários', data?.users.length], ['Localizações', data?.locations.length]].map(([label, value]) => <article className="stat-card" key={String(label)}><span>{label}</span><strong>{value ?? '—'}</strong></article>)}
    </div>
    <div className="overview-grid"><section className="overview-map panel"><div className="panel-heading"><div><h3>Na estrada</h3><p>Últimas posições reportadas</p></div><button className="ghost" onClick={() => onPage('map')}>Abrir mapa ↗</button></div><div className="map-container"><MapView reports={data?.locations ?? []} /></div></section>
    </div>
  </div>;
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
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
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
      const live = isLiveLocation(r.reportedAt, now);
      const marker = L.marker([r.lat, r.lng], {
        icon: L.divIcon({
          className: 'beacon-marker',
          html: (() => { const pin = document.createElement('div'); pin.className = `beacon-marker__pin ${live ? 'is-live' : 'is-stale'}`; pin.textContent = r.username ? r.username[0].toUpperCase() : '?'; return pin; })(),
          iconSize: [32, 32],
          iconAnchor: [16, 16],
        }),
      });
      const popup = document.createElement('div');
      const name = document.createElement('strong');
      name.textContent = r.username;
      const status = document.createElement('div');
      status.className = live ? 'location-live' : 'location-stale';
      status.textContent = live ? 'Em tempo real' : 'Sem atualização recente';
      popup.append(name, document.createElement('br'), document.createTextNode(`${r.lat.toFixed(5)}, ${r.lng.toFixed(5)}`), document.createElement('br'), document.createTextNode(new Date(r.reportedAt).toLocaleString('pt-BR')));
      popup.append(status);
      marker.bindPopup(popup);
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
  }, [reports, now]);

  return <><div className="leaflet-container" ref={elRef} /><div className="map-legend" aria-label="Status da localização"><span><i className="legend-live" />Em tempo real</span><span><i className="legend-stale" />Sem atualização recente</span><small>Tempo real: posição recebida há até 1 minuto</small></div></>;
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
    setDrafts((prev) => ({ ...prev, [u.id]: { ...u, ...prev[u.id], ...patch } }));
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

function ChannelsPage({
  api,
  onUnauthorized,
}: {
  api: Api;
  onUnauthorized: () => void;
}) {
  const [data, setData] = useState<ApiPage<AdminChannel> | null>(null);
  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);

  const load = useCallback(async () => {
    try {
      const result = await api.listChannels(search, page);
      setData(result as ApiPage<AdminChannel>);
      setError(null);
      setLoaded(true);
    } catch (e) {
      if (unauthorizedMessage(e)) {
        onUnauthorized();
        return;
      }
      setError(e instanceof Error ? e.message : 'Falha ao listar canais');
    }
  }, [api, search, page, onUnauthorized]);

  useEffect(() => {
    load();
    const id = setInterval(load, POLL_INTERVAL_MS);
    return () => clearInterval(id);
  }, [load]);

  const submitSearch = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setPage(1);
    setSearch(searchInput.trim());
  };

  const remove = async (channel: AdminChannel) => {
    if (
      !window.confirm(
        `Excluir o canal "${channel.name}"? Esta ação não pode ser desfeita.`,
      )
    ) {
      return;
    }
    setDeletingId(channel.id);
    setError(null);
    setSuccess(null);
    try {
      await api.deleteChannel(channel.id);
      setSuccess(`Canal "${channel.name}" excluído.`);
      await load();
    } catch (e) {
      if (unauthorizedMessage(e)) {
        onUnauthorized();
        return;
      }
      setError(e instanceof Error ? e.message : 'Falha ao excluir o canal');
    } finally {
      setDeletingId(null);
    }
  };

  const total = data?.total ?? 0;
  const pageSize = data?.pageSize ?? 20;
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  const channels = data?.items ?? [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>Canais</h2>
        <span className="meta">
          {total} canal(is) · atualiza a cada {POLL_INTERVAL_MS / 1000}s
          {!loaded && ' · carregando...'}
        </span>
        {error && <span className="error">{error}</span>}
        {success && <span className="success">{success}</span>}
        <button className="ghost" onClick={load}>
          Atualizar
        </button>
      </div>

      <form className="filters" onSubmit={submitSearch}>
        <label>
          Buscar
          <input
            value={searchInput}
            placeholder="Nome do canal"
            onChange={(e) => setSearchInput(e.target.value)}
          />
        </label>
        <button className="primary" type="submit">
          Filtrar
        </button>
      </form>

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Canal</th>
              <th>Dono</th>
              <th>Tipo</th>
              <th>Online agora</th>
              <th>Criado em</th>
              <th className="actions-col">Ações</th>
            </tr>
          </thead>
          <tbody>
            {channels.map((c) => (
              <tr key={c.id}>
                <td className="cell-user">{c.name}</td>
                <td>{c.owner || '—'}</td>
                <td className="muted">
                  {c.isPrivate ? 'Privado' : 'Público'}
                </td>
                <td>
                  <span className={`badge ${c.online > 0 ? 'badge-live' : 'badge-off'}`}>
                    {c.online > 0 ? `${c.online} online` : '0 online'}
                  </span>
                </td>
                <td className="muted">
                  {c.createdAt
                    ? new Date(c.createdAt).toLocaleString()
                    : '—'}
                </td>
                <td className="actions-col">
                  <button
                    className="danger"
                    disabled={deletingId != null || c.online > 0}
                    title={
                      c.online > 0
                        ? 'Há pessoas conectadas neste canal'
                        : 'Excluir canal'
                    }
                    onClick={() => remove(c)}
                  >
                    {deletingId === c.id ? 'Excluindo...' : 'Excluir'}
                  </button>
                </td>
              </tr>
            ))}
            {channels.length === 0 && !error && (
              <tr>
                <td colSpan={6} className="muted center">
                  {loaded ? 'Nenhum canal encontrado.' : 'Carregando...'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="pagination">
        <button
          className="ghost"
          disabled={page <= 1}
          onClick={() => setPage((p) => Math.max(1, p - 1))}
        >
          ‹ Anterior
        </button>
        <span className="muted">
          Página {page} de {totalPages}
        </span>
        <button
          className="ghost"
          disabled={page >= totalPages}
          onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
        >
          Próxima ›
        </button>
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
