export type Role = 'user' | 'admin';

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
