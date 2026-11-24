package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
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

type orbitsByIdentifier struct {
	orbit.Repository
	byIdentifier map[string]*orbit.Orbit
}

func (r *orbitsByIdentifier) FindByIdentifier(_ context.Context, identifier string) (*orbit.Orbit, error) {
	if o, ok := r.byIdentifier[identifier]; ok {
		return o, nil
	}
	return nil, orbit.ErrNotFound
}

func TestReportEncounter(t *testing.T) {
	active, _ := orbit.New("Orbit do Lucas", "ORBIT-LUCAS")
	inactive, _ := orbit.New("Orbit parado", "ORBIT-OFF")
	inactive.Active = false
	orbits := &orbitsByIdentifier{byIdentifier: map[string]*orbit.Orbit{
		active.Identifier:   active,
		inactive.Identifier: inactive,
	}}
	u := &user.User{ID: uuid.New(), Username: "motorista"}

	cases := []struct {
		name   string
		body   string
		status int
	}{
		{"encontro válido", `{"lat":-23.5,"lng":-46.6,"orbit":{"identifier":" ORBIT-LUCAS ","rssi":-60}}`, http.StatusNoContent},
		{"sem orbit", `{"lat":-23.5,"lng":-46.6}`, http.StatusBadRequest},
		{"orbit não cadastrado", `{"lat":-23.5,"lng":-46.6,"orbit":{"identifier":"ORBIT-X"}}`, http.StatusUnprocessableEntity},
		{"orbit inativo", `{"lat":-23.5,"lng":-46.6,"orbit":{"identifier":"ORBIT-OFF"}}`, http.StatusUnprocessableEntity},
		{"coordenada inválida", `{"lat":-123.5,"lng":-46.6,"orbit":{"identifier":"ORBIT-LUCAS"}}`, http.StatusBadRequest},
		{"hora no futuro", `{"lat":-23.5,"lng":-46.6,"orbit":{"identifier":"ORBIT-LUCAS"},"at":"2999-01-01T00:00:00Z"}`, http.StatusBadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			locations := &savedLocations{}
			h := NewLocationHandler(locations, orbits)
			req := httptest.NewRequest(http.MethodPost, "/api/v1/locations", strings.NewReader(tc.body))
			req = req.WithContext(middleware.WithUser(req.Context(), u))
			res := httptest.NewRecorder()

			h.Report(res, req)

			if res.Code != tc.status {
				t.Fatalf("status = %d, want %d (%s)", res.Code, tc.status, res.Body.String())
			}
			if tc.status != http.StatusNoContent {
				if len(locations.saved) != 0 {
					t.Fatal("rejected encounter must not be saved")
				}
				return
			}
			loc := locations.saved[0]
			if *loc.OrbitID != active.ID || *loc.OrbitName != active.Name || *loc.RSSI != -60 || loc.UserID != u.ID {
				t.Fatalf("unexpected saved location: %+v", loc)
			}
		})
	}
}

// Encontro que ficou na fila sem internet: chega depois, com a hora real e o
// id gerado no app.
func TestReportQueuedEncounter(t *testing.T) {
	o, _ := orbit.New("Orbit do Lucas", "ORBIT-LUCAS")
	orbits := &orbitsByIdentifier{byIdentifier: map[string]*orbit.Orbit{o.Identifier: o}}
	locations := &savedLocations{}
	h := NewLocationHandler(locations, orbits)
	u := &user.User{ID: uuid.New(), Username: "motorista"}
	id := uuid.New()
	at := time.Now().Add(-3 * time.Hour).UTC().Truncate(time.Second)

	body := `{"id":"` + id.String() + `","lat":-23.5,"lng":-46.6,"orbit":{"identifier":"ORBIT-LUCAS"},"at":"` + at.Format(time.RFC3339) + `"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/locations", strings.NewReader(body))
	req = req.WithContext(middleware.WithUser(req.Context(), u))
	res := httptest.NewRecorder()

	h.Report(res, req)

	if res.Code != http.StatusNoContent {
		t.Fatalf("status = %d (%s)", res.Code, res.Body.String())
	}
	loc := locations.saved[0]
	if loc.ID != id || !loc.CreatedAt.Equal(at) {
		t.Fatalf("got id %v at %v, want %v at %v", loc.ID, loc.CreatedAt, id, at)
	}
}
