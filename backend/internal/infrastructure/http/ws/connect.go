package ws

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"sync"

	"github.com/coder/websocket"
	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/application/channel"
	"github.com/lucas/radio-px-backend/internal/domain/location"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	"github.com/lucas/radio-px-backend/internal/infrastructure/auth/jwt"
)

type Handler struct {
	channelGate  sync.RWMutex
	hub          *Hub
	logger       *slog.Logger
	tokenManager *jwt.Manager
	users        user.Repository
	channels     *channel.Service
	locations    location.Repository
}

func NewHandler(
	hub *Hub,
	logger *slog.Logger,
	tokenManager *jwt.Manager,
	users user.Repository,
	channels *channel.Service,
	locations location.Repository,
) *Handler {
	return &Handler{
		hub:          hub,
		logger:       logger,
		tokenManager: tokenManager,
		users:        users,
		channels:     channels,
		locations:    locations,
	}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		writeHubError(w, http.StatusUnauthorized, "missing token")
		return
	}

	claims, err := h.tokenManager.ParseAccessToken(token)
	if err != nil {
		writeHubError(w, http.StatusUnauthorized, "invalid token")
		return
	}

	channelID, err := uuid.Parse(r.URL.Query().Get("channel_id"))
	if err != nil {
		writeHubError(w, http.StatusBadRequest, "invalid channel_id")
		return
	}

	// How far the client already listened. Optional and untrusted: the queue
	// falls back to sending everything when the value makes no sense.
	lastHeardSeq, _ := strconv.ParseInt(r.URL.Query().Get("last_heard_seq"), 10, 64)
	if lastHeardSeq < 0 {
		lastHeardSeq = 0
	}

	u, err := h.users.FindByID(r.Context(), claims.UserID)
	if err != nil {
		writeHubError(w, http.StatusUnauthorized, "user not found")
		return
	}
	// Keep membership checks and attachment atomic relative to admin deletion.
	h.channelGate.RLock()
	gateHeld := true
	defer func() {
		if gateHeld {
			h.channelGate.RUnlock()
		}
	}()

	isMember, err := h.channels.IsMember(r.Context(), channelID, u.ID)
	if err != nil || !isMember {
		writeHubError(w, http.StatusForbidden, "not a member of this channel")
		return
	}

	ch, err := h.channels.Get(r.Context(), channelID)
	if err != nil {
		writeHubError(w, http.StatusNotFound, "channel not found")
		return
	}

	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		InsecureSkipVerify: true,
	})
	if err != nil {
		return
	}

	room := h.hub.getOrCreateRoom(channelID, ch.Name)
	client := newClient(room, u, conn, h.locations)

	// Let the client know who is already here.
	client.send(outboundMessage{
		Type:      msgJoined,
		Room:      &roomInfo{ID: room.id, Name: room.name},
		Members:   room.members(),
		Locations: room.allLocations(),
		UserID:    client.user.ID,
	})

	// Attach the member and stream the audio they still owe themselves before
	// announcing their presence, so they hear pending clips in order, before
	// live ones.
	room.attachAndSnapshot(client, lastHeardSeq)
	room.broadcast(outboundMessage{Type: msgPeerJoin, UserID: client.user.ID, Username: client.user.Username})
	gateHeld = false
	h.channelGate.RUnlock()

	go client.writePump()
	go client.pingLoop()
	client.readLoop()
}

var ErrChannelInUse = errors.New("channel is in use")

// DeleteIdleChannel prevents deleting channels with active radio connections.
func (h *Handler) DeleteIdleChannel(ctx context.Context, id uuid.UUID, remove func(context.Context, uuid.UUID) error) error {
	h.channelGate.Lock()
	defer h.channelGate.Unlock()
	h.hub.mu.RLock()
	room := h.hub.rooms[id]
	h.hub.mu.RUnlock()
	if room != nil {
		room.mu.RLock()
		active := len(room.clients) > 0
		room.mu.RUnlock()
		if active {
			return ErrChannelInUse
		}
	}
	if err := remove(ctx, id); err != nil {
		return err
	}
	h.hub.mu.Lock()
	delete(h.hub.rooms, id)
	delete(h.hub.queues, id)
	h.hub.mu.Unlock()
	return nil
}

func writeHubError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": message})
}
