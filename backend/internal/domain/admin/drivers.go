package admin

import (
	"sort"
	"time"

	"github.com/google/uuid"
)

// DriverStatus is how the panel classifies a driver from the signals the
// server has: the radio WebSocket (only while inside a channel) and the
// background GPS beacon (running since login, even with the app closed).
type DriverStatus string

const (
	// DriverOpen: connected to a radio channel right now.
	DriverOpen DriverStatus = "open"
	// DriverClosed: not in a channel, but the beacon reported recently.
	DriverClosed DriverStatus = "closed"
	// DriverOffline: no signal within the window.
	DriverOffline DriverStatus = "offline"
)

// BeaconWindow is how long a beacon report keeps a driver out of offline. The
// beacon reports at least every 30 seconds, so this tolerates a few misses.
const BeaconWindow = 3 * time.Minute

// DriverRecord is a driver as stored: profile plus the last reported position.
type DriverRecord struct {
	ID           uuid.UUID
	Username     string
	FirstName    string
	LastName     string
	VehiclePlate string
	Lat          *float64
	Lng          *float64
	ReportedAt   *time.Time
}

type Driver struct {
	ID           uuid.UUID    `json:"id"`
	Username     string       `json:"username"`
	FirstName    string       `json:"firstName"`
	LastName     string       `json:"lastName"`
	VehiclePlate string       `json:"vehiclePlate"`
	Status       DriverStatus `json:"status"`
	Channel      string       `json:"channel,omitempty"`
	Lat          *float64     `json:"lat,omitempty"`
	Lng          *float64     `json:"lng,omitempty"`
	LastSeenAt   *time.Time   `json:"lastSeenAt,omitempty"`
}

type DriverCounts struct {
	Total   int `json:"total"`
	Open    int `json:"open"`
	Closed  int `json:"closed"`
	Offline int `json:"offline"`
}

type DriversOverview struct {
	Counts              DriverCounts `json:"counts"`
	Drivers             []Driver     `json:"drivers"`
	BeaconWindowSeconds int          `json:"beaconWindowSeconds"`
}

var statusOrder = map[DriverStatus]int{DriverOpen: 0, DriverClosed: 1, DriverOffline: 2}

// BuildDriversOverview classifies each driver. connected maps the users with
// an active radio connection to the name of their channel.
func BuildDriversOverview(records []DriverRecord, connected map[uuid.UUID]string, now time.Time) DriversOverview {
	out := DriversOverview{Drivers: make([]Driver, 0, len(records)), BeaconWindowSeconds: int(BeaconWindow.Seconds())}
	for _, rec := range records {
		d := Driver{
			ID:           rec.ID,
			Username:     rec.Username,
			FirstName:    rec.FirstName,
			LastName:     rec.LastName,
			VehiclePlate: rec.VehiclePlate,
			Lat:          rec.Lat,
			Lng:          rec.Lng,
			LastSeenAt:   rec.ReportedAt,
			Status:       DriverOffline,
		}
		if channel, ok := connected[rec.ID]; ok {
			d.Status = DriverOpen
			d.Channel = channel
		} else if rec.ReportedAt != nil && now.Sub(*rec.ReportedAt) <= BeaconWindow {
			d.Status = DriverClosed
		}
		switch d.Status {
		case DriverOpen:
			out.Counts.Open++
		case DriverClosed:
			out.Counts.Closed++
		default:
			out.Counts.Offline++
		}
		out.Drivers = append(out.Drivers, d)
	}
	out.Counts.Total = len(out.Drivers)
	sort.SliceStable(out.Drivers, func(i, j int) bool {
		a, b := out.Drivers[i], out.Drivers[j]
		if statusOrder[a.Status] != statusOrder[b.Status] {
			return statusOrder[a.Status] < statusOrder[b.Status]
		}
		return a.Username < b.Username
	})
	return out
}
