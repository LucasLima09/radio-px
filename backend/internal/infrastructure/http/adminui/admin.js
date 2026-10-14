'use strict';

const $ = (id) => document.getElementById(id);
const number = new Intl.NumberFormat('pt-BR');
const date = new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' });
let session = null;
let tab = 'channels';
let page = 1;
let query = '';
let generation = 0;
let authGeneration = 0;
let selectedChannel = null;
let refreshPromise = null;
let deleting = false;

function message(id, text = '', success = false) {
  const target = $(id);
  target.textContent = text;
  target.classList.toggle('success', success);
}

async function request(path, options = {}, retry = true) {
  const authVersion = authGeneration;
  let response;
  try {
    response = await fetch(`/api/v1${path}`, {
      ...options,
      headers: { 'Content-Type': 'application/json', ...(session ? { Authorization: `Bearer ${session.accessToken}` } : {}) },
      cache: 'no-store',
    });
  } catch (_) { throw new Error('Não foi possível conectar ao servidor. Tente novamente.'); }
  if (response.status === 401 && session && retry && authVersion === authGeneration) {
    if (!refreshPromise) {
      const pending = request('/auth/refresh', {
        method: 'POST', body: JSON.stringify({ refreshToken: session.refreshToken }),
      }, false).finally(() => { if (refreshPromise === pending) refreshPromise = null; });
      refreshPromise = pending;
    }
    try {
      const renewed = await refreshPromise;
      if (!session || authVersion !== authGeneration) throw new Error('Sessão encerrada.');
      session = renewed;
    } catch (_) {
      if (authVersion === authGeneration) {
        showLogin();
        message('login-message', 'Sua sessão expirou. Entre novamente.');
      }
      throw new Error('Sua sessão expirou.');
    }
    return request(path, options, false);
  }
  if (response.status === 204) return null;
  let data;
  try { data = await response.json(); }
  catch (_) { throw new Error('O servidor retornou uma resposta inválida.'); }
  if (!response.ok) {
    const detail = response.status === 401 ? 'Usuário ou senha incorretos.' : data.error || 'Não foi possível concluir a ação.';
    const error = new Error(detail);
    error.status = response.status;
    throw error;
  }
  return data;
}

function showLogin() {
  stopDriverMap();
  session = null;
  authGeneration++;
  refreshPromise = null;
  generation++;
  $('dashboard-view').hidden = true;
  $('login-view').hidden = false;
  $('delete-dialog').close();
  $('password').value = '';
  $('username').focus();
}

$('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = $('login-submit');
  if (button.disabled) return;
  button.disabled = true;
  button.textContent = 'Entrando…';
  message('login-message');
  try {
    session = await request('/auth/login', { method: 'POST', body: JSON.stringify({ username: $('username').value.trim(), password: $('password').value }) });
    const admin = await request('/admin/me');
    $('admin-name').textContent = admin.username;
    $('user-initial').textContent = admin.username.charAt(0).toUpperCase();
    $('password').value = '';
    $('login-view').hidden = true;
    $('dashboard-view').hidden = false;
    startDriverMap();
    tab = 'channels'; page = 1; query = ''; $('search').value = '';
    updateTab();
    await load();
    $('section-title').setAttribute('tabindex', '-1');
    $('section-title').focus();
  } catch (error) {
    const failedSession = session;
    showLogin();
    message('login-message', error.message);
    if (failedSession) {
      fetch('/api/v1/auth/logout', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${failedSession.accessToken}` }, body: JSON.stringify({ refreshToken: failedSession.refreshToken }) }).catch(() => {});
    }
  } finally { button.disabled = false; button.textContent = 'Entrar no painel ↗'; }
});

$('logout').addEventListener('click', async () => {
  const previous = session;
  showLogin();
  if (previous) {
    try {
      await fetch('/api/v1/auth/logout', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${previous.accessToken}` }, body: JSON.stringify({ refreshToken: previous.refreshToken }) });
    } catch (_) { /* Tokens are discarded locally even when the server is offline. */ }
  }
});

function updateTab() {
  const channels = tab === 'channels';
  document.querySelectorAll('[data-tab]').forEach((button) => {
    const active = button.dataset.tab === tab;
    button.classList.toggle('active', active);
    if (active) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  });
  $('section-title').textContent = channels ? 'Canais' : 'Usuários';
  $('section-description').textContent = channels ? 'Consulte os canais e remova os que não são mais necessários.' : 'Consulte quem faz parte da sua rede.';
  $('search').placeholder = channels ? 'Buscar canal por nome…' : 'Buscar usuário por nome…';
  $('table-caption').textContent = channels ? 'Canais cadastrados' : 'Usuários cadastrados';
}

document.querySelectorAll('[data-tab]').forEach((button) => button.addEventListener('click', () => {
  if (button.dataset.tab === tab) return;
  tab = button.dataset.tab; page = 1; query = ''; $('search').value = '';
  updateTab(); load();
}));
$('search-form').addEventListener('submit', (event) => { event.preventDefault(); query = $('search').value.trim(); page = 1; load(); });
$('search').addEventListener('search', () => { if (!$('search').value) { query = ''; page = 1; load(); } });
$('previous').addEventListener('click', () => { if (page > 1) { page--; load(); } });
$('next').addEventListener('click', () => { page++; load(); });
$('refresh').addEventListener('click', () => { load(); refreshDrivers(); });

function element(tag, text = '', className = '') {
  const node = document.createElement(tag);
  node.textContent = text;
  if (className) node.className = className;
  return node;
}

function renderTable(data, currentTab) {
  const channels = currentTab === 'channels';
  const head = element('tr');
  for (const label of channels ? ['Canal', 'Criado por', 'Membros', 'Acesso', ''] : ['Usuário', 'Cadastro', 'ID']) {
    const th = element('th', label); th.scope = 'col'; head.append(th);
  }
  $('table-head').replaceChildren(head);
  $('table-body').replaceChildren();
  for (const item of data.items) {
    const row = element('tr');
    const nameCell = element('td');
    const name = element('div', '', 'cell-name');
    name.append(element('span', channels ? '#' : item.username.charAt(0).toUpperCase(), 'cell-icon'));
    const nameText = element('div');
    nameText.append(element('span', channels ? item.name : item.username));
    if (channels) nameText.append(element('p', date.format(new Date(item.createdAt)), 'subtext'));
    name.append(nameText); nameCell.append(name); row.append(nameCell);
    if (channels) {
      row.append(element('td', item.owner), element('td', number.format(item.members)));
      const access = element('td'); access.append(element('span', item.isPrivate ? 'Privado' : 'Público', 'badge')); row.append(access);
      const action = element('td');
      const button = element('button', 'Excluir', 'delete-button');
      button.setAttribute('aria-label', `Excluir canal ${item.name}`);
      button.addEventListener('click', () => openDelete(item)); action.append(button); row.append(action);
    } else {
      const id = element('td', item.id, 'muted');
      row.append(element('td', date.format(new Date(item.createdAt))), id);
    }
    $('table-body').append(row);
  }
  $('table-wrapper').hidden = data.items.length === 0;
  $('table-status').textContent = data.items.length ? '' : query ? 'Nenhum resultado para essa busca.' : channels ? 'Nenhum canal criado ainda.' : 'Nenhum usuário cadastrado.';
  $('result-count').textContent = `${number.format(data.total)} ${channels ? 'canais' : 'usuários'}`;
  const pages = Math.max(1, Math.ceil(data.total / data.pageSize));
  $('page-info').textContent = `Página ${data.page} de ${pages}`;
  $('previous').disabled = data.page <= 1;
  $('next').disabled = data.page >= pages;
}

async function load(clearMessage = true) {
  if (!session) return;
  const version = ++generation;
  const currentTab = tab;
  if (clearMessage) message('dashboard-message');
  $('table-wrapper').hidden = true;
  $('table-status').textContent = 'Carregando…';
  $('result-count').textContent = '—'; $('page-info').textContent = '—';
  $('previous').disabled = true; $('next').disabled = true;
  $('refresh').disabled = true;
  try {
    const [summary, data] = await Promise.all([
      request('/admin/summary'), request(`/admin/${currentTab}?q=${encodeURIComponent(query)}&page=${page}`),
    ]);
    if (version !== generation || !session) return;
    if (data.items.length === 0 && data.page > 1 && data.total > 0) {
      page = Math.max(1, Math.ceil(data.total / data.pageSize));
      return load(clearMessage);
    }
    $('stat-users').textContent = number.format(summary.users);
    $('stat-channels').textContent = number.format(summary.channels);
    $('stat-memberships').textContent = number.format(summary.memberships);
    renderTable(data, currentTab);
  } catch (error) {
    if (version !== generation) return;
    if (error.status === 403) { showLogin(); message('login-message', error.message); return; }
    $('table-status').textContent = 'Os dados não puderam ser carregados. Clique em Atualizar para tentar novamente.';
    for (const id of ['stat-users', 'stat-channels', 'stat-memberships']) $(id).textContent = '—';
    message('dashboard-message', error.message);
  } finally { if (version === generation) $('refresh').disabled = false; }
}

function openDelete(channel) {
  selectedChannel = channel;
  $('delete-name').textContent = channel.name;
  message('delete-message');
  $('delete-dialog').showModal();
  $('cancel-delete').focus();
}
$('cancel-delete').addEventListener('click', () => { if (!deleting) $('delete-dialog').close(); });
$('delete-dialog').addEventListener('cancel', (event) => { if (deleting) event.preventDefault(); });
$('delete-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  if (deleting || !selectedChannel) return;
  deleting = true;
  $('confirm-delete').disabled = true; $('cancel-delete').disabled = true;
  $('confirm-delete').textContent = 'Excluindo…'; message('delete-message');
  try {
    await request(`/admin/channels/${selectedChannel.id}`, { method: 'DELETE' });
    $('delete-dialog').close();
    message('dashboard-message', 'Canal excluído.', true);
    await load(false);
  } catch (error) { message('delete-message', error.message); }
  finally {
    deleting = false;
    $('confirm-delete').disabled = false; $('cancel-delete').disabled = false;
    $('confirm-delete').textContent = 'Excluir canal';
  }
});

let driverMap = null;
let driverTimer = null;
let driverEpoch = 0;
let driverBusy = false;
let driverMarkers = new Map();
let drivers = [];
let framedDrivers = false;

function stopDriverMap() {
  driverEpoch++;
  clearTimeout(driverTimer);
  driverTimer = null;
  driverBusy = false;
  drivers = [];
  driverMarkers.forEach(marker => marker.remove());
  driverMarkers.clear();
  $('driver-list').replaceChildren();
  framedDrivers = false;
}

function startDriverMap() {
  stopDriverMap();
  if (!window.L) {
    $('map-message').textContent = 'Não foi possível carregar o mapa. Recarregue a página.';
    return;
  }
  if (!driverMap) {
    driverMap = L.map('driver-map').setView([-14.2, -51.9], 4);
    const tiles = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    }).addTo(driverMap);
    tiles.on('tileerror', () => {
      $('map-message').textContent = 'Não foi possível carregar parte do mapa. Verifique a conexão com a internet.';
    });
  }
  requestAnimationFrame(() => driverMap.invalidateSize());
  $('driver-count').textContent = 'Carregando posições…';
  $('map-status').textContent = '';
  refreshDrivers();
}

function fitDrivers() {
  if (drivers.length) driverMap.fitBounds(drivers.map(d => [d.lat, d.lng]), { padding: [40, 40], maxZoom: 15 });
}
$('fit-drivers').addEventListener('click', fitDrivers);

function renderDrivers() {
  const ids = new Set(drivers.map(d => d.userId));
  driverMarkers.forEach((marker, id) => {
    if (!ids.has(id)) { marker.remove(); driverMarkers.delete(id); }
  });
  $('driver-list').replaceChildren();
  let staleCount = 0;
  for (const driver of drivers) {
    const age = Math.max(0, Math.floor((Date.now() - new Date(driver.updatedAt).getTime()) / 1000));
    const stale = age > 90;
    if (stale) staleCount++;
    const time = new Date(driver.updatedAt).toLocaleTimeString('pt-BR');
    const detail = `${driver.channel} · ${stale ? 'Posição antiga' : 'Posição recente'} · GPS às ${time}`;
    const popup = element('div');
    popup.append(element('strong', driver.username), element('p', detail));
    let marker = driverMarkers.get(driver.userId);
    if (!marker) {
      marker = L.circleMarker([driver.lat, driver.lng], { radius: 9, weight: 3, fillOpacity: .9 }).addTo(driverMap);
      marker.bindPopup(popup);
      driverMarkers.set(driver.userId, marker);
    } else {
      marker.setLatLng([driver.lat, driver.lng]);
      marker.setPopupContent(popup);
    }
    marker.setStyle({ color: stale ? '#dca648' : '#218d75', fillColor: stale ? '#ffd27a' : '#80e1c3' });
    const button = element('button', '', 'driver-card');
    button.append(element('strong', driver.username), element('small', detail));
    button.addEventListener('click', () => { driverMap.setView([driver.lat, driver.lng], 16); marker.openPopup(); });
    $('driver-list').append(button);
  }
  $('driver-count').textContent = `${drivers.length} motorista${drivers.length === 1 ? '' : 's'} no mapa`;
  $('map-message').textContent = drivers.length ? (staleCount ? `${staleCount} posição(ões) aguardando atualização do GPS.` : '') : 'Nenhum motorista compartilhando localização. Entre em um canal no aplicativo e permita o GPS para aparecer aqui.';
  $('fit-drivers').disabled = drivers.length === 0;
  if (drivers.length && !framedDrivers) { fitDrivers(); framedDrivers = true; }
}

async function refreshDrivers() {
  if (!session || !driverMap || driverBusy) return;
  clearTimeout(driverTimer);
  const epoch = driverEpoch;
  driverBusy = true;
  try {
    const data = await request('/admin/locations', { signal: AbortSignal.timeout(15000) });
    if (epoch !== driverEpoch || !session) return;
    drivers = data;
    renderDrivers();
    $('map-status').textContent = `Sincronizado às ${new Date().toLocaleTimeString('pt-BR')}`;
  } catch (error) {
    if (epoch !== driverEpoch || !session) return;
    if (error.status === 403) { showLogin(); message('login-message', error.message); return; }
    $('map-status').textContent = 'Sem conexão · tentando novamente';
    $('map-message').textContent = 'Atualização interrompida. Os marcadores mostram a última posição recebida.';
  } finally {
    if (epoch === driverEpoch) {
      driverBusy = false;
      if (session) driverTimer = setTimeout(refreshDrivers, document.hidden ? 10000 : 2000);
    }
  }
}

document.addEventListener('visibilitychange', () => { if (!document.hidden) refreshDrivers(); });
