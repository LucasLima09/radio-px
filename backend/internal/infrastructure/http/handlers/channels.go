package handlers

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	channelapp "github.com/lucas/radio-px-backend/internal/application/channel"
	domainchannel "github.com/lucas/radio-px-backend/internal/domain/channel"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
)

type ChannelHandler struct {
	service *channelapp.Service
	online  OnlineCounter
}

// OnlineCounter exposes how many users are currently connected to each channel.
// Implemented by the WebSocket hub; the channel service itself does not track
// live presence.
type OnlineCounter interface {
	ChannelOnline() map[uuid.UUID]int
}

func NewChannelHandler(service *channelapp.Service, online OnlineCounter) *ChannelHandler {
	return &ChannelHandler{service: service, online: online}
}

// withOnline fills the live online count for each channel. Channels with no
// active room stay at 0.
func (h *ChannelHandler) withOnline(channels []domainchannel.Public) {
	if h.online == nil {
		return
	}
	counts := h.online.ChannelOnline()
	for i := range channels {
		channels[i].Online = counts[channels[i].ID]
	}
}

type createChannelRequest struct {
	Name      string `json:"name"`
	IsPrivate bool   `json:"isPrivate"`
	Password  string `json:"password"`
}

type joinChannelRequest struct {
	Password string `json:"password"`
}

func (h *ChannelHandler) Create(w http.ResponseWriter, r *http.Request) {
	u, ok := middleware.UserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req createChannelRequest
	if err := decodeJSON(w, r, &req); err != nil {
		return
	}

	created, err := h.service.Create(r.Context(), channelapp.CreateInput{
		OwnerID:   u.ID,
		Name:      req.Name,
		IsPrivate: req.IsPrivate,
		Password:  req.Password,
	})
	if err != nil {
		writeDomainError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, created)
}

func (h *ChannelHandler) List(w http.ResponseWriter, r *http.Request) {
	_, ok := middleware.UserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	channels := h.service.List(r.Context())
	h.withOnline(channels)
	writeJSON(w, http.StatusOK, channels)
}

func (h *ChannelHandler) Get(w http.ResponseWriter, r *http.Request) {
	_, ok := middleware.UserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	id, err := uuid.Parse(chi.URLParam(r, "channelID"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid channel id")
		return
	}

	ch, err := h.service.Get(r.Context(), id)
	if err != nil {
		writeDomainError(w, err)
		return
	}
	if h.online != nil {
		ch.Online = h.online.ChannelOnline()[ch.ID]
	}

	writeJSON(w, http.StatusOK, ch)
}

func (h *ChannelHandler) Join(w http.ResponseWriter, r *http.Request) {
	u, ok := middleware.UserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	id, err := uuid.Parse(chi.URLParam(r, "channelID"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid channel id")
		return
	}

	// The body is optional: public channels and returning members need none.
	var req joinChannelRequest
	if r.ContentLength != 0 {
		if err := decodeJSON(w, r, &req); err != nil {
			return
		}
	}

	ch, err := h.service.Join(r.Context(), id, u.ID, req.Password)
	if err != nil {
		writeDomainError(w, err)
		return
	}
	if h.online != nil {
		ch.Online = h.online.ChannelOnline()[ch.ID]
	}

	writeJSON(w, http.StatusOK, ch)
}
