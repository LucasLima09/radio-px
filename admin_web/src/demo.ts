import { Api, type LocationReport, type PublicUser } from './api';

export class DemoApi extends Api {
  private users: PublicUser[] = [
    { id: 'demo-admin', username: 'Admin Demo', role: 'admin', createdAt: '2026-09-01T12:00:00Z' },
    { id: 'demo-1', username: 'Carlos Silva', role: 'user', createdAt: '2026-09-12T12:00:00Z' },
    { id: 'demo-2', username: 'Ana Souza', role: 'user', createdAt: '2026-09-15T12:00:00Z' },
    { id: 'demo-3', username: 'Pedro Santos', role: 'user', createdAt: '2026-09-20T12:00:00Z' },
  ];
  private locations: LocationReport[];

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
  override async logout() { this.user = null; }
}
