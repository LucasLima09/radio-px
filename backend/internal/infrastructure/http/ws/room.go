package ws

import (
	"encoding/json"
	"sync"

	"github.com/google/uuid"
)

type Room struct {
	hub  *Hub
	id   uuid.UUID
	name string

	mu        sync.RWMutex
	clients   map[*Client]struct{}
	locations map[*Client]locationInfo
	recording map[*Client]struct{}
}

func newRoom(hub *Hub, id uuid.UUID, name string) *Room {
	return &Room{
		hub:       hub,
		id:        id,
		name:      name,
		clients:   make(map[*Client]struct{}),
		locations: make(map[*Client]locationInfo),
		recording: make(map[*Client]struct{}),
	}
}

func (r *Room) add(c *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.addLocked(c)
}

func (r *Room) addLocked(c *Client) {
	r.clients[c] = struct{}{}
}

// attachAndSnapshot adds the client to the room and, atomically, sends it a
// snapshot of the pending audio queue. Doing both under the same lock
// guarantees arrival order and avoids clips being delivered twice (live and
// via snapshot).
func (r *Room) attachAndSnapshot(c *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	snapshot := r.hub.queueFor(r.id).snapshot()
	r.addLocked(c)
	for _, clip := range snapshot {
		c.sendClip(clip)
	}
}

func (r *Room) members() []memberInfo {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]memberInfo, 0, len(r.clients))
	for c := range r.clients {
		_, rec := r.recording[c]
		out = append(out, newMemberInfo(c.user, rec))
	}
	return out
}

func (r *Room) broadcast(m outboundMessage) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	r.broadcastLocked(m)
}

// updateLocation stores the latest known position for a member and broadcasts
// it to every client in the room.
func (r *Room) updateLocation(c *Client, lat, lng float64) {
	r.mu.Lock()
	r.locations[c] = locationInfo{UserID: c.user.ID, Username: c.user.Username, Lat: lat, Lng: lng}
	r.broadcastLocked(outboundMessage{Type: msgLocationUpdate, UserID: c.user.ID, Username: c.user.Username, Lat: lat, Lng: lng})
	r.mu.Unlock()
}

// allLocations returns the last known position of every member that has
// reported one. Used to build the joined snapshot for a new client.
func (r *Room) allLocations() []locationInfo {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]locationInfo, 0, len(r.locations))
	for _, loc := range r.locations {
		out = append(out, loc)
	}
	return out
}

// setRecording flips a member's recording state and notifies everyone.
func (r *Room) setRecording(c *Client, recording bool) {
	r.mu.Lock()
	typ := msgRecordingStop
	if recording {
		r.recording[c] = struct{}{}
		typ = msgRecordingStart
	} else {
		delete(r.recording, c)
	}
	r.broadcastLocked(outboundMessage{
		Type:     typ,
		UserID:   c.user.ID,
		Username: c.user.Username,
	})
	r.mu.Unlock()
}

// broadcastClip delivers a clip (metadata + binary payload) to every member,
// including its author.
func (r *Room) broadcastClip(clip *Clip) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	for c := range r.clients {
		c.sendClip(clip)
	}
}

// broadcastLocked requires r.mu to be held.
func (r *Room) broadcastLocked(m outboundMessage) {
	data, err := json.Marshal(m)
	if err != nil {
		return
	}
	for c := range r.clients {
		c.pushFrame(outboundFrame{Kind: frameText, Data: data})
	}
}

func (r *Room) remove(c *Client) {
	r.mu.Lock()
	if _, ok := r.clients[c]; !ok {
		r.mu.Unlock()
		return
	}
	delete(r.clients, c)
	delete(r.locations, c)
	delete(r.recording, c)
	r.broadcastLocked(outboundMessage{Type: msgPeerLeft, UserID: c.user.ID})
	empty := len(r.clients) == 0
	r.mu.Unlock()

	if empty {
		r.hub.removeRoom(r.id)
	}
}
