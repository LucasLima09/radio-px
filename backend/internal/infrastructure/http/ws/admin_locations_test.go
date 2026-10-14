package ws

import (
	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	"io"
	"log/slog"
	"testing"
	"time"
)

func TestDriverLocationsConnectedLatestPerUser(t *testing.T) {
	hub := NewHub(slog.New(slog.NewTextHandler(io.Discard, nil)), time.Minute, 10, 1024, 4096)
	defer hub.Stop()
	handler := &Handler{hub: hub}
	if got := handler.DriverLocations(); got == nil || len(got) != 0 {
		t.Fatal("empty snapshot must be a JSON array")
	}
	driver := &user.User{ID: uuid.New(), Username: "motorista"}
	first := hub.getOrCreateRoom(uuid.New(), "Primeiro")
	second := hub.getOrCreateRoom(uuid.New(), "Segundo")
	a := newClient(first, driver, nil, nil)
	b := newClient(second, driver, nil, nil)
	first.add(a)
	second.add(b)
	first.updateLocation(a, -23.5, -46.6)
	first.locationTimes[a] = time.Now().Add(-time.Minute)
	second.updateLocation(b, -22.9, -43.2)
	got := handler.DriverLocations()
	if len(got) != 1 || got[0].Channel != "Segundo" || got[0].Lat != -22.9 || got[0].UpdatedAt.IsZero() {
		t.Fatalf("unexpected newest position: %+v", got)
	}
	second.remove(b)
	got = handler.DriverLocations()
	if len(got) != 1 || got[0].Channel != "Primeiro" {
		t.Fatalf("disconnected client still visible: %+v", got)
	}
	first.remove(a)
	if len(handler.DriverLocations()) != 0 {
		t.Fatal("disconnected driver should disappear")
	}
}
