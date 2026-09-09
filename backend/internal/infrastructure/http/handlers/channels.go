package handlers

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	channelapp "github.com/lucas/radio-px-backend/internal/application/channel"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
)

type ChannelHandler struct {
	service *channelapp.Service
}

func NewChannelHandler(service *channelapp.Service) *ChannelHandler {
	return &ChannelHandler{service: service}
}

type createChannelRequest struct {
	Name      string `json:"name"`
	IsPrivate bool   `json:"isPrivate"`
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
	})
	if err != nil {
		writeDomainError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, created)
}

func (h *ChannelHandler) List(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, h.service.List(r.Context()))
}

func (h *ChannelHandler) Get(w http.ResponseWriter, r *http.Request) {
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

	ch, err := h.service.Join(r.Context(), id, u.ID)
	if err != nil {
		writeDomainError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, ch)
}
