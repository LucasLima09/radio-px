package admin

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestBuildDriversOverviewClassifiesBySignal(t *testing.T) {
	now := time.Date(2026, 10, 29, 12, 0, 0, 0, time.UTC)
	recent := now.Add(-time.Minute)
	old := now.Add(-BeaconWindow - time.Second)

	inChannel := DriverRecord{ID: uuid.New(), Username: "carla", ReportedAt: &old}
	beaconOnly := DriverRecord{ID: uuid.New(), Username: "bruno", ReportedAt: &recent}
	stale := DriverRecord{ID: uuid.New(), Username: "ana", ReportedAt: &old}
	never := DriverRecord{ID: uuid.New(), Username: "davi"}

	got := BuildDriversOverview(
		[]DriverRecord{stale, never, beaconOnly, inChannel},
		map[uuid.UUID]string{inChannel.ID: "Central"},
		now,
	)

	want := DriverCounts{Total: 4, Open: 1, Closed: 1, Offline: 2}
	if got.Counts != want {
		t.Fatalf("counts = %+v, want %+v", got.Counts, want)
	}
	order := []string{"carla", "bruno", "ana", "davi"}
	for i, name := range order {
		if got.Drivers[i].Username != name {
			t.Fatalf("position %d = %s, want %s (open, closed, offline, then by name)", i, got.Drivers[i].Username, name)
		}
	}
	if got.Drivers[0].Status != DriverOpen || got.Drivers[0].Channel != "Central" {
		t.Fatalf("connected driver must be open in its channel: %+v", got.Drivers[0])
	}
	if got.Drivers[1].Status != DriverClosed {
		t.Fatalf("recent beacon without channel must be closed: %+v", got.Drivers[1])
	}
}
