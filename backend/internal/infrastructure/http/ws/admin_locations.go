package ws

import (
	"github.com/google/uuid"
	"sort"
	"time"
)

type DriverLocation struct {
	UserID    uuid.UUID `json:"userId"`
	Username  string    `json:"username"`
	ChannelID uuid.UUID `json:"channelId"`
	Channel   string    `json:"channel"`
	Lat       float64   `json:"lat"`
	Lng       float64   `json:"lng"`
	UpdatedAt time.Time `json:"updatedAt"`
}

// DriverLocations snapshots connected clients only, keeping the newest position
// when one account is connected from multiple devices or channels.
func (h *Handler) DriverLocations() []DriverLocation {
	h.hub.mu.RLock()
	rooms := make([]*Room, 0, len(h.hub.rooms))
	for _, room := range h.hub.rooms {
		rooms = append(rooms, room)
	}
	h.hub.mu.RUnlock()
	latest := make(map[uuid.UUID]DriverLocation)
	for _, room := range rooms {
		room.mu.RLock()
		for client, loc := range room.locations {
			if _, connected := room.clients[client]; !connected {
				continue
			}
			at := room.locationTimes[client]
			if old, exists := latest[loc.UserID]; exists && !at.After(old.UpdatedAt) {
				continue
			}
			latest[loc.UserID] = DriverLocation{loc.UserID, loc.Username, room.id, room.name, loc.Lat, loc.Lng, at}
		}
		room.mu.RUnlock()
	}
	result := make([]DriverLocation, 0, len(latest))
	for _, loc := range latest {
		result = append(result, loc)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].Username < result[j].Username })
	return result
}
