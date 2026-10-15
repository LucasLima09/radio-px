package ws

import "github.com/google/uuid"

// ChannelOnline returns how many distinct users are currently connected to each
// active channel. Channels without an active room are absent (online = 0).
func (h *Handler) ChannelOnline() map[uuid.UUID]int {
	h.hub.mu.RLock()
	rooms := make([]*Room, 0, len(h.hub.rooms))
	for _, room := range h.hub.rooms {
		rooms = append(rooms, room)
	}
	h.hub.mu.RUnlock()

	counts := make(map[uuid.UUID]int, len(rooms))
	for _, room := range rooms {
		if n := room.onlineUsers(); n > 0 {
			counts[room.id] = n
		}
	}
	return counts
}
