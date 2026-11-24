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
  /** Orbit encontrado via Bluetooth que gerou o report (ausente nas posições antigas de GPS). */
  orbitName?: string;
  /** Intensidade do sinal Bluetooth no encontro, em dBm. */
  rssi?: number;
  reportedAt: string;
}

/** Orbit cadastrado: reconhecido pelos apps via Bluetooth pelo identificador. */
export interface Orbit {
  id: string;
  name: string;
  /** Nome que o dispositivo anuncia no Bluetooth. */
  identifier: string;
  active: boolean;
  createdAt: string;
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

/** open: conectado a um canal; closed: fora do canal com GPS ativo; offline: sem sinal. */
export type DriverStatus = 'open' | 'closed' | 'offline';

export interface Driver {
  id: string;
  username: string;
  firstName: string;
  lastName: string;
  vehiclePlate: string;
  status: DriverStatus;
  channel?: string;
  lat?: number;
  lng?: number;
  lastSeenAt?: string;
}

export interface DriversOverview {
  counts: { total: number; open: number; closed: number; offline: number };
  drivers: Driver[];
  beaconWindowSeconds: number;
}
