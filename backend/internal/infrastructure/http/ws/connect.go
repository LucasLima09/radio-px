package ws

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/coder/websocket"
	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/application/channel"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	"github.com/lucas/radio-px-backend/internal/infrastructure/auth/jwt"
)

type Handler struct {
	hub          *Hub
	logger       *slog.Logger
	tokenManager *jwt.Manager
	users        user.Repository
	channels     *channel.Service
}

func NewHandler(
	hub *Hub,
	logger *slog.Logger,
	tokenManager *jwt.Manager,
	users user.Repository,
	channels *channel.Service,
) *Handler {
	return &Handler{
		hub:          hub,
		logger:       logger,
		tokenManager: tokenManager,
		users:        users,
		channels:     channels,
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

	u, err := h.users.FindByID(r.Context(), claims.UserID)
	if err != nil {
		writeHubError(w, http.StatusUnauthorized, "user not found")
		return
	}

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
	client := newClient(room, u, conn, h.hub.stunServers)
	room.add(client)

	// Let the client know who is already here.
	talker := room.activeTalker()
	client.send(outboundMessage{
		Type:    msgJoined,
		Room:    &roomInfo{ID: room.id, Name: room.name},
		Members: room.members(),
		UserID:  client.user.ID,
	})
	if talker != nil {
		client.send(outboundMessage{Type: msgTalkStart, UserID: talker.user.ID, Username: talker.user.Username})
	}

	if err := client.setupReceivePC(); err != nil {
		h.logger.Error("setup receive peer connection", "error", err)
		client.close()
		return
	}

	// Wire this member into an ongoing talk before announcing their presence.
	room.attachNewMember(client)
	room.broadcast(outboundMessage{Type: msgPeerJoin, UserID: client.user.ID, Username: client.user.Username})

	go client.writePump()
	client.readLoop()
}

func writeHubError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": message})
}
