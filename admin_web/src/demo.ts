import { Api, type AdminChannel, type LocationReport, type Page, type PublicUser } from './api';

export class DemoApi extends Api {
  private users: PublicUser[] = [
    { id: 'demo-admin', username: 'Admin Demo', role: 'admin', createdAt: '2026-09-01T12:00:00Z' },
    { id: 'demo-1', username: 'Carlos Silva', role: 'user', createdAt: '2026-09-12T12:00:00Z' },
    { id: 'demo-2', username: 'Ana Souza', role: 'user', createdAt: '2026-09-15T12:00:00Z' },
    { id: 'demo-3', username: 'Pedro Santos', role: 'user', createdAt: '2026-09-20T12:00:00Z' },
  ];
  private locations: LocationReport[];
  private channels: AdminChannel[] = [
    { id: 'chan-1', name: 'Frota Centro', owner: 'Admin Demo', online: 3, members: 8, isPrivate: false, createdAt: '2026-09-05T12:00:00Z' },
    { id: 'chan-2', name: 'Entrega Norte', owner: 'Carlos Silva', online: 1, members: 4, isPrivate: false, createdAt: '2026-09-08T12:00:00Z' },
    { id: 'chan-3', name: 'Operação VIP', owner: 'Ana Souza', online: 0, members: 2, isPrivate: true, createdAt: '2026-09-11T12:00:00Z' },
  ];

  constructor() {
    super('demo');
    this.user = { ...this.users[0] };
    this.locations = [
      { userId: 'demo-1', username: 'Carlos Silva', lat: -23.5505, lng: -46.6333, reportedAt: new Date(Date.now() - 60000).toISOString() },
      { userId: 'demo-2', username: 'Ana Souza', lat: -23.4543, lng: -46.5337, reportedAt: new Date(Date.now() - 180000).toISOString() },
      { userId: 'demo-3', username: 'Pedro Santos', lat: -23.6914, lng: -46.5646, reportedAt: new Date(Date.now() - 300000).toISOString() },
    ];
  }

  override get hasSession() { return true; }
  override async listUsers() { return this.users.map((u) => ({ ...u })); }
  override async latestLocations() {
    // One simulated driver keeps reporting; the others retain their last position.
    const active = this.locations.find((r) => r.userId === 'demo-1');
    if (active) active.reportedAt = new Date().toISOString();
    return this.locations.map((r) => ({ ...r }));
  }
  override async locationHistory(userId?: string, limit = 200) {
    return this.locations.filter((r) => !userId || r.userId === userId).slice(0, limit).map((r) => ({ ...r }));
  }
  override async updateUser(id: string, patch: { username?: string; role?: string }) {
    const user = this.users.find((u) => u.id === id);
    if (!user) throw new Error('Usuário não encontrado');
    Object.assign(user, patch);
    this.locations.forEach((r) => { if (r.userId === id) r.username = user.username; });
    if (this.user?.id === id) this.user = { ...user };
    return { ...user };
  }
  override async deleteUser(id: string) {
    if (id === this.user?.id) throw new Error('Você não pode excluir sua própria conta');
    this.users = this.users.filter((u) => u.id !== id);
    this.locations = this.locations.filter((r) => r.userId !== id);
  }
  override async listChannels(search = '', page = 1): Promise<Page<AdminChannel>> {
    const pageSize = 20;
    const term = search.trim().toLowerCase();
    const filtered = this.channels.filter((c) => !term || c.name.toLowerCase().includes(term));
    const start = (page - 1) * pageSize;
    return {
      items: filtered.slice(start, start + pageSize).map((c) => ({ ...c })),
      total: filtered.length,
      page,
      pageSize,
    };
  }
  override async deleteChannel(id: string) {
    const channel = this.channels.find((c) => c.id === id);
    if (!channel) throw new Error('Canal não encontrado');
    if (channel.online > 0) throw new Error('O canal está em uso. Aguarde os participantes saírem.');
    this.channels = this.channels.filter((c) => c.id !== id);
  }
  override async logout() { this.user = null; }
}
