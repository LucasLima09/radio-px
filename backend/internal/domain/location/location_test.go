package location

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/orbit"
)

func signalAt(at time.Time) orbit.Signal {
	return orbit.Signal{At: at, Latitude: -23.5, Longitude: -46.6}
}

func TestNewEncounter(t *testing.T) {
	o := orbit.Discovered("A1B2C3D401020304")
	rssi := -60
	// Ficou 2 h na fila do app sem internet.
	at := time.Now().Add(-2 * time.Hour).Truncate(time.Second)
	loc, err := NewEncounter(uuid.New(), signalAt(at), o, &rssi)
	if err != nil {
		t.Fatalf("NewEncounter: %v", err)
	}
	if *loc.OrbitID != o.ID || *loc.OrbitName != o.Name || *loc.RSSI != -60 {
		t.Fatalf("unexpected orbit fields: %v %q %d", *loc.OrbitID, *loc.OrbitName, *loc.RSSI)
	}
	if loc.Latitude != -23.5 || loc.Longitude != -46.6 || !loc.CreatedAt.Equal(at) {
		t.Fatalf("position and time must come from the signal: %+v", loc)
	}
	if loc.ChannelID != nil {
		t.Fatal("encounter must not reference a channel")
	}

	// O nome gravado é uma cópia: renomear o Orbit depois não altera o histórico.
	name := *loc.OrbitName
	_ = o.Rename("Outro nome")
	if *loc.OrbitName != name {
		t.Fatalf("orbit name must be a snapshot, got %q", *loc.OrbitName)
	}
}

func TestNewEncounterRejects(t *testing.T) {
	o := orbit.Discovered("A1B2C3D401020304")
	bad := 50
	now := time.Now()
	old := now.Add(-31 * 24 * time.Hour)
	cases := []struct {
		name   string
		signal orbit.Signal
		rssi   *int
		want   error
	}{
		{"latitude", orbit.Signal{At: now, Latitude: 91}, nil, ErrInvalidCoord},
		{"longitude", orbit.Signal{At: now, Longitude: -181}, nil, ErrInvalidCoord},
		{"rssi", signalAt(now), &bad, ErrInvalidRSSI},
		{"futuro", signalAt(now.Add(time.Hour)), nil, ErrInvalidTime},
		{"velho demais", signalAt(old), nil, ErrInvalidTime},
	}
	for _, c := range cases {
		if _, err := NewEncounter(uuid.New(), c.signal, o, c.rssi); err != c.want {
			t.Fatalf("%s: got %v, want %v", c.name, err, c.want)
		}
	}
}
