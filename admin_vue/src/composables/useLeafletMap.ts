import { markRaw, onBeforeUnmount, onMounted, watch, type Ref } from 'vue';
import L from 'leaflet';

import { formatDateTime, initial } from '@/utils/format';
import { isLiveLocation } from '@/utils/location-status';
import type { LocationReport } from '@/types';

const DEFAULT_CENTER: L.LatLngTuple = [-23.5505, -46.6333];
const DEFAULT_ZOOM = 5;
const SINGLE_ZOOM = 14;

interface MarkerEntry {
  marker: L.Marker;
  live: boolean;
  letter: string;
}

function pinIcon(letter: string, live: boolean): L.DivIcon {
  const pin = document.createElement('div');
  pin.className = `beacon-marker__pin ${live ? 'is-live' : 'is-stale'}`;
  pin.textContent = letter;
  return L.divIcon({ className: 'beacon-marker', html: pin, iconSize: [32, 32], iconAnchor: [16, 16] });
}

// Montado via DOM (textContent) para não interpretar nomes de usuário como HTML.
function popupContent(r: LocationReport, live: boolean): HTMLElement {
  const popup = document.createElement('div');
  const name = document.createElement('strong');
  name.textContent = r.username;
  const status = document.createElement('div');
  status.className = live ? 'location-live' : 'location-stale';
  status.textContent = live ? 'Em tempo real' : 'Sem atualização recente';
  popup.append(
    name,
    document.createElement('br'),
    document.createTextNode(`${r.lat.toFixed(5)}, ${r.lng.toFixed(5)}`),
    document.createElement('br'),
    document.createTextNode(formatDateTime(r.reportedAt)),
    status,
  );
  return popup;
}

/**
 * Mapa Leaflet com um marcador por usuário. Os marcadores são atualizados no
 * lugar (posição, ícone, popup), então um popup aberto não fecha no polling.
 */
export function useLeafletMap(
  container: Ref<HTMLElement | null>,
  reports: Ref<LocationReport[]>,
  now: Ref<number>,
) {
  let map: L.Map | null = null;
  const markers = new Map<string, MarkerEntry>();
  let fittedIds = '';

  function render(): void {
    if (!map) return;
    const seen = new Set<string>();

    for (const r of reports.value) {
      seen.add(r.userId);
      const live = isLiveLocation(r.reportedAt, now.value);
      const letter = initial(r.username);
      const entry = markers.get(r.userId);

      if (!entry) {
        const marker = markRaw(L.marker([r.lat, r.lng], { icon: pinIcon(letter, live) }));
        marker.bindPopup(popupContent(r, live)).addTo(map);
        markers.set(r.userId, { marker, live, letter });
        continue;
      }
      entry.marker.setLatLng([r.lat, r.lng]);
      if (entry.live !== live || entry.letter !== letter) {
        entry.marker.setIcon(pinIcon(letter, live));
        entry.live = live;
        entry.letter = letter;
      }
      entry.marker.setPopupContent(popupContent(r, live));
    }

    for (const [userId, entry] of markers) {
      if (seen.has(userId)) continue;
      entry.marker.remove();
      markers.delete(userId);
    }

    fitToReports();
  }

  // Reenquadra só quando o conjunto de usuários muda, para não brigar com o zoom do admin.
  function fitToReports(): void {
    const list = reports.value;
    const ids = list.map((r) => r.userId).join('|');
    if (!map || list.length === 0 || ids === fittedIds) return;
    fittedIds = ids;
    if (list.length === 1) {
      map.setView([list[0].lat, list[0].lng], SINGLE_ZOOM);
    } else {
      map.fitBounds(L.latLngBounds(list.map((r) => [r.lat, r.lng] as L.LatLngTuple)), {
        padding: [48, 48],
      });
    }
  }

  onMounted(() => {
    if (!container.value) return;
    map = markRaw(L.map(container.value).setView(DEFAULT_CENTER, DEFAULT_ZOOM));
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap',
    }).addTo(map);
    render();
  });

  watch([reports, now], render);

  onBeforeUnmount(() => {
    map?.remove();
    map = null;
    markers.clear();
    fittedIds = '';
  });
}
