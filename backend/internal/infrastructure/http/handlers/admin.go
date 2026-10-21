package handlers

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/admin"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/ws"
)

type AdminHandler struct {
	repo   admin.Repository
	ws     *ws.Handler
	logger *slog.Logger
}

func NewAdminHandler(repo admin.Repository, wsHandler *ws.Handler, logger *slog.Logger) *AdminHandler {
	return &AdminHandler{repo: repo, ws: wsHandler, logger: logger}
}

func (h *AdminHandler) Me(w http.ResponseWriter, r *http.Request) {
	u, _ := middleware.UserFromContext(r.Context())
	writeJSON(w, http.StatusOK, u.Public())
}

func (h *AdminHandler) Locations(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, h.ws.DriverLocations())
}

func (h *AdminHandler) Summary(w http.ResponseWriter, r *http.Request) {
	result, err := h.repo.Summary(r.Context())
	if err != nil {
		h.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func adminQuery(w http.ResponseWriter, r *http.Request) (string, int, bool) {
	search := strings.TrimSpace(r.URL.Query().Get("q"))
	page := 1
	if raw := r.URL.Query().Get("page"); raw != "" {
		value, err := strconv.Atoi(raw)
		if err != nil || value < 1 || value > 100000 {
			writeError(w, 400, "Página inválida.")
			return "", 0, false
		}
		page = value
	}
	if len(search) > 100 {
		writeError(w, 400, "Busca muito longa.")
		return "", 0, false
	}
	return search, page, true
}

func (h *AdminHandler) Users(w http.ResponseWriter, r *http.Request) {
	search, page, ok := adminQuery(w, r)
	if !ok {
		return
	}
	result, err := h.repo.Users(r.Context(), search, page)
	if err != nil {
		h.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (h *AdminHandler) Channels(w http.ResponseWriter, r *http.Request) {
	search, page, ok := adminQuery(w, r)
	if !ok {
		return
	}
	result, err := h.repo.Channels(r.Context(), search, page)
	if err != nil {
		h.fail(w, r, err)
		return
	}
	if online := h.ws.ChannelOnline(); len(online) > 0 {
		for i := range result.Items {
			result.Items[i].Online = online[result.Items[i].ID]
		}
	}
	writeJSON(w, http.StatusOK, result)
}

func (h *AdminHandler) DeleteChannel(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(chi.URLParam(r, "channelID"))
	if err != nil {
		writeError(w, 400, "Canal inválido.")
		return
	}
	err = h.ws.DeleteIdleChannel(r.Context(), id, h.repo.DeleteChannel)
	if errors.Is(err, ws.ErrChannelInUse) {
		writeError(w, http.StatusConflict, "O canal está em uso. Aguarde os participantes saírem.")
		return
	}
	if err != nil {
		writeDomainError(w, err)
		return
	}
	u, _ := middleware.UserFromContext(r.Context())
	h.logger.Info("admin deleted channel", "user_id", u.ID, "channel_id", id)
	w.WriteHeader(http.StatusNoContent)
}

func (h *AdminHandler) fail(w http.ResponseWriter, r *http.Request, err error) {
	h.logger.Error("admin request failed", "path", r.URL.Path, "error", err)
	writeError(w, 500, "Não foi possível carregar os dados. Tente novamente.")
}
