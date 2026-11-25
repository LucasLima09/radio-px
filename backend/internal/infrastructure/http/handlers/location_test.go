package handlers

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/location"
	"github.com/lucas/radio-px-backend/internal/domain/orbit"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
)

type savedLocations struct {
	location.Repository
	saved []*location.Location
}

func (r *savedLocations) Save(_ context.Context, loc *location.Location) error {
	r.saved = append(r.saved, loc)
	return nil
}

type orbitsInMemory struct {
	orbit.Repository
	byIdentifier map[string]*orbit.Orbit
}

func (r *orbitsInMemory) Ensure(_ context.Context, identifier string) (*orbit.Orbit, error) {
	if o, ok := r.byIdentifier[identifier]; ok {
		return o, nil
	}
	o := orbit.Discovered(identifier)
	r.byIdentifier[identifier] = o
	return o, nil
}

func privateKey(fill byte) ed25519.PrivateKey {
	return ed25519.NewKeyFromSeed(bytes.Repeat([]byte{fill}, ed25519.SeedSize))
}

func report(t *testing.T, h *LocationHandler, u *user.User, body any) *httptest.ResponseRecorder {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/locations", bytes.NewReader(raw))
	req = req.WithContext(middleware.WithUser(req.Context(), u))
	res := httptest.NewRecorder()
	h.Report(res, req)
	return res
}

func TestReportSignal(t *testing.T) {
	key := privateKey(1)
	public := key.Public().(ed25519.PublicKey)
	u := &user.User{ID: uuid.New(), Username: "motorista"}
	now := time.Now().UTC().Truncate(time.Second)
	device := [8]byte{1, 2, 3, 4, 5, 6, 7, 8}
	blocked := [8]byte{9, 9, 9, 9, 9, 9, 9, 9}
	signal := func(id [8]byte, at time.Time, lat float64, k ed25519.PrivateKey) []byte {
		return orbit.Signal{DeviceID: id, At: at, Latitude: lat, Longitude: -46.6}.Sign(k)
	}
	tampered := signal(device, now, -23.5, key)
	tampered[13] ^= 1 // latitude alterada depois de assinada

	cases := []struct {
		name   string
		body   map[string]any
		status int
	}{
		{"sinal válido de Orbit nunca visto", map[string]any{"signal": signal(device, now, -23.5, key), "rssi": -60}, http.StatusNoContent},
		{"sem sinal", map[string]any{}, http.StatusBadRequest},
		{"sinal curto", map[string]any{"signal": []byte("oi")}, http.StatusBadRequest},
		{"assinado por outra chave", map[string]any{"signal": signal(device, now, -23.5, privateKey(2))}, http.StatusUnprocessableEntity},
		{"posição adulterada", map[string]any{"signal": tampered}, http.StatusUnprocessableEntity},
		{"orbit desativado", map[string]any{"signal": signal(blocked, now, -23.5, key)}, http.StatusUnprocessableEntity},
		{"coordenada inválida", map[string]any{"signal": signal(device, now, -123.5, key)}, http.StatusBadRequest},
		{"hora do Orbit no futuro", map[string]any{"signal": signal(device, now.Add(time.Hour), -23.5, key)}, http.StatusBadRequest},
		{"coordenada solta é ignorada", map[string]any{"lat": -23.5, "lng": -46.6}, http.StatusBadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			off := orbit.Discovered(orbit.Signal{DeviceID: blocked}.Identifier())
			off.Active = false
			orbits := &orbitsInMemory{byIdentifier: map[string]*orbit.Orbit{off.Identifier: off}}
			locations := &savedLocations{}

			res := report(t, NewLocationHandler(locations, orbits, public), u, tc.body)

			if res.Code != tc.status {
				t.Fatalf("status = %d, want %d (%s)", res.Code, tc.status, res.Body.String())
			}
			if tc.status != http.StatusNoContent {
				if len(locations.saved) != 0 || len(orbits.byIdentifier) != 1 {
					t.Fatal("rejected signal must not save a location nor create an orbit")
				}
				return
			}
			created := orbits.byIdentifier["0102030405060708"]
			loc := locations.saved[0]
			if created == nil || *loc.OrbitID != created.ID || *loc.RSSI != -60 || loc.UserID != u.ID {
				t.Fatalf("unexpected saved location: %+v", loc)
			}
			if loc.Latitude != -23.5 || loc.Longitude != -46.6 || !loc.CreatedAt.Equal(now) {
				t.Fatalf("position and time must come from the signal: %+v", loc)
			}
		})
	}
}

// Encontro que ficou na fila sem internet, em um celular com a hora errada: vale
// a hora do Orbit.
func TestReportQueuedSignal(t *testing.T) {
	key := privateKey(1)
	locations := &savedLocations{}
	orbits := &orbitsInMemory{byIdentifier: map[string]*orbit.Orbit{}}
	h := NewLocationHandler(locations, orbits, key.Public().(ed25519.PublicKey))
	id := uuid.New()
	at := time.Now().Add(-3 * time.Hour).UTC().Truncate(time.Second)

	res := report(t, h, &user.User{ID: uuid.New()}, map[string]any{
		"id":     id,
		"signal": orbit.Signal{At: at, Latitude: 1, Longitude: 2}.Sign(key),
		"at":     at.Add(26 * time.Hour),
	})

	if res.Code != http.StatusNoContent {
		t.Fatalf("status = %d (%s)", res.Code, res.Body.String())
	}
	if loc := locations.saved[0]; loc.ID != id || !loc.CreatedAt.Equal(at) {
		t.Fatalf("got id %v at %v", loc.ID, loc.CreatedAt)
	}
}

// Sem a chave o servidor não tem como conferir nada: pede para tentar depois,
// e o app mantém o encontro na fila.
func TestReportWithoutKey(t *testing.T) {
	h := NewLocationHandler(&savedLocations{}, &orbitsInMemory{}, nil)
	res := report(t, h, &user.User{ID: uuid.New()}, map[string]any{})
	if res.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d", res.Code)
	}
}
