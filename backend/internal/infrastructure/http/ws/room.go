package ws

import (
	"context"
	"encoding/json"
	"errors"
	"sync"

	"github.com/google/uuid"
	"github.com/pion/webrtc/v4"
)

var errTalkBusy = errors.New("channel is busy")

type Room struct {
	hub  *Hub
	id   uuid.UUID
	name string

	mu      sync.RWMutex
	clients map[*Client]struct{}

	// talk state (a PX channel allows a single talker at a time)
	talker        *Client
	talkSource    *webrtc.TrackRemote
	talkTracks    map[*Client][]*localTrack
	forwardCancel context.CancelFunc
}

func newRoom(hub *Hub, id uuid.UUID, name string) *Room {
	return &Room{
		hub:        hub,
		id:         id,
		name:       name,
		clients:    make(map[*Client]struct{}),
		talkTracks: make(map[*Client][]*localTrack),
	}
}

func (r *Room) add(c *Client) {
	r.mu.Lock()
	r.clients[c] = struct{}{}
	r.mu.Unlock()
}

func (r *Room) members() []memberInfo {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]memberInfo, 0, len(r.clients))
	for c := range r.clients {
		out = append(out, newMemberInfo(c.user, r.talker == c))
	}
	return out
}

func (r *Room) activeTalker() *Client {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.talker
}

func (r *Room) broadcast(m outboundMessage) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	r.broadcastLocked(m)
}

// broadcastLocked requires r.mu to be held.
func (r *Room) broadcastLocked(m outboundMessage) {
	data, err := json.Marshal(m)
	if err != nil {
		return
	}
	for c := range r.clients {
		select {
		case c.sendCh <- data:
		default:
		}
	}
}

// startTalk registers c as the room talker and fans out its track to every
// other member. Returns errTalkBusy when another member is already talking.
func (r *Room) startTalk(c *Client, track *webrtc.TrackRemote) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.talker != nil && r.talker != c {
		return errTalkBusy
	}
	r.talker = c
	r.talkSource = track

	for other := range r.clients {
		if other == c {
			continue
		}
		if r.addFanOutLocked(other, track) != nil {
			other.renegotiateRecv()
		}
	}

	r.forwardCancel = startForwarder(context.Background(), track, r.fanOutLocalsLocked)

	r.broadcastLocked(outboundMessage{Type: msgTalkStart, UserID: c.user.ID, Username: c.user.Username})
	return nil
}

// attachNewMember wires a member that joined while a talk is in progress.
func (r *Room) attachNewMember(c *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.talkSource == nil {
		return
	}
	if r.addFanOutLocked(c, r.talkSource) != nil {
		c.renegotiateRecv()
	}
}

func (r *Room) addFanOutLocked(c *Client, track *webrtc.TrackRemote) *localTrack {
	local, err := newFanOutTrack(track)
	if err != nil {
		return nil
	}
	sender, err := c.addFanOutTrack(local)
	if err != nil {
		return nil
	}
	lt := &localTrack{local: local, sender: sender}
	r.talkTracks[c] = append(r.talkTracks[c], lt)
	return lt
}

func (r *Room) fanOutLocalsLocked() []*webrtc.TrackLocalStaticRTP {
	var out []*webrtc.TrackLocalStaticRTP
	for _, tracks := range r.talkTracks {
		for _, t := range tracks {
			out = append(out, t.local)
		}
	}
	return out
}

func (r *Room) stopTalk(c *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.stopTalkLocked(c)
}

// stopTalkLocked requires r.mu to be held.
func (r *Room) stopTalkLocked(c *Client) {
	if r.talker != c {
		return
	}
	if r.forwardCancel != nil {
		r.forwardCancel()
		r.forwardCancel = nil
	}

	for cl, tracks := range r.talkTracks {
		for _, t := range tracks {
			_ = cl.removeFanOutTrack(t)
		}
		if len(tracks) > 0 {
			cl.renegotiateRecv()
		}
	}

	r.talkTracks = make(map[*Client][]*localTrack)
	r.talkSource = nil
	r.talker = nil

	c.closePublishPC()
	r.broadcastLocked(outboundMessage{Type: msgTalkStop, UserID: c.user.ID})
}

func (r *Room) remove(c *Client) {
	r.mu.Lock()
	if _, ok := r.clients[c]; !ok {
		r.mu.Unlock()
		return
	}
	delete(r.clients, c)

	if r.talker == c {
		r.stopTalkLocked(c)
	}

	delete(r.talkTracks, c)
	r.broadcastLocked(outboundMessage{Type: msgPeerLeft, UserID: c.user.ID})
	empty := len(r.clients) == 0
	r.mu.Unlock()

	if empty {
		r.hub.removeRoom(r.id)
	}
}
