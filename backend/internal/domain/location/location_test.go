package location

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/orbit"
)

func TestNewEncounter(t *testing.T) {
	o, _ := orbit.New("Orbit do Lucas", "ORBIT-LUCAS")
	rssi := -60
	at := time.Now().Add(-2 * time.Hour)
	loc, err := NewEncounter(uuid.New(), -23.5, -46.6, o, &rssi, at)
	if err != nil {
		t.Fatalf("NewEncounter: %v", err)
	}
	if *loc.OrbitID != o.ID || *loc.OrbitName != "Orbit do Lucas" || *loc.RSSI != -60 {
		t.Fatalf("unexpected orbit fields: %v %q %d", *loc.OrbitID, *loc.OrbitName, *loc.RSSI)
	}
	if !loc.CreatedAt.Equal(at.UTC()) {
		t.Fatalf("created_at must be the encounter time, got %v", loc.CreatedAt)
	}
	if loc.ChannelID != nil {
		t.Fatal("encounter must not reference a channel")
	}

	// O nome gravado é uma cópia: renomear o Orbit depois não altera o histórico.
	_ = o.Rename("Outro nome", "ORBIT-LUCAS")
	if *loc.OrbitName != "Orbit do Lucas" {
		t.Fatalf("orbit name must be a snapshot, got %q", *loc.OrbitName)
	}
}

func TestNewEncounterRejects(t *testing.T) {
	o, _ := orbit.New("Orbit", "ORBIT")
	bad := 50
	now := time.Now()
	cases := []struct {
		lat, lng float64
		rssi     *int
		at       time.Time
		want     error
	}{
		{91, 0, nil, now, ErrInvalidCoord},
		{0, -181, nil, now, ErrInvalidCoord},
		{0, 0, &bad, now, ErrInvalidRSSI},
		{0, 0, nil, now.Add(time.Hour), ErrInvalidTime},
		{0, 0, nil, now.Add(-31 * 24 * time.Hour), ErrInvalidTime},
	}
	for _, c := range cases {
		if _, err := NewEncounter(uuid.New(), c.lat, c.lng, o, c.rssi, c.at); err != c.want {
			t.Fatalf("NewEncounter(%v, %v) = %v, want %v", c.lat, c.lng, err, c.want)
		}
	}
}
