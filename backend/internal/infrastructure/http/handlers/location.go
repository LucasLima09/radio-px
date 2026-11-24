package handlers

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/location"
	"github.com/lucas/radio-px-backend/internal/domain/orbit"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
)

type LocationHandler struct {
	locations location.Repository
	orbits    orbit.Repository
}

func NewLocationHandler(locations location.Repository, orbits orbit.Repository) *LocationHandler {
	return &LocationHandler{locations: locations, orbits: orbits}
}

type orbitRequest struct {
	// Identifier é o nome que o Orbit anuncia no Bluetooth.
	Identifier string `json:"identifier"`
	RSSI       *int   `json:"rssi"`
}

type reportLocationRequest struct {
	// ID gerado pelo app para o encontro. Torna o envio idempotente: o app
	// reenvia o que ficou na fila sem saber se a resposta anterior se perdeu.
	ID    *uuid.UUID    `json:"id"`
	Lat   float64       `json:"lat"`
	Lng   float64       `json:"lng"`
	Orbit *orbitRequest `json:"orbit"`
	// At é a hora do encontro no aparelho (RFC 3339). Sem ela, vale a hora
	// de chegada.
	At *time.Time `json:"at"`
}

// Report persiste a posição do usuário no momento em que o app encontrou um
// Orbit cadastrado via Bluetooth. A localização só é aceita junto de um
// encontro: sem orbit, responde 400; com um Orbit não cadastrado ou inativo,
// 422. Fica fora de canal, por isso o channel_id é nil. Reenviar o mesmo id
// responde 204 sem gravar de novo.
func (h *LocationHandler) Report(w http.ResponseWriter, r *http.Request) {
	u, ok := middleware.UserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req reportLocationRequest
	if err := decodeJSON(w, r, &req); err != nil {
		return
	}

	if req.Orbit == nil {
		writeError(w, http.StatusBadRequest, "orbit is required")
		return
	}

	o, err := h.orbits.FindByIdentifier(r.Context(), strings.TrimSpace(req.Orbit.Identifier))
	if errors.Is(err, orbit.ErrNotFound) || (err == nil && !o.Active) {
		writeError(w, http.StatusUnprocessableEntity, "unknown orbit")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal server error")
		return
	}

	var at time.Time
	if req.At != nil {
		at = *req.At
	}
	loc, err := location.NewEncounter(u.ID, req.Lat, req.Lng, o, req.Orbit.RSSI, at)
	if errors.Is(err, location.ErrInvalidTime) {
		writeError(w, http.StatusBadRequest, "invalid encounter time")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid location")
		return
	}
	if req.ID != nil {
		loc.ID = *req.ID
	}

	if err := h.locations.Save(r.Context(), loc); err != nil {
		writeError(w, http.StatusInternalServerError, "internal server error")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

type locationReportResponse struct {
	UserID     uuid.UUID `json:"userId"`
	Username   string    `json:"username"`
	Lat        float64   `json:"lat"`
	Lng        float64   `json:"lng"`
	OrbitName  *string   `json:"orbitName,omitempty"`
	RSSI       *int      `json:"rssi,omitempty"`
	ReportedAt time.Time `json:"reportedAt"`
}

func toReportResponses(reports []location.Report) []locationReportResponse {
	out := make([]locationReportResponse, 0, len(reports))
	for _, rep := range reports {
		out = append(out, locationReportResponse{
			UserID:     rep.UserID,
			Username:   rep.Username,
			Lat:        rep.Latitude,
			Lng:        rep.Longitude,
			OrbitName:  rep.OrbitName,
			RSSI:       rep.RSSI,
			ReportedAt: rep.ReportedAt,
		})
	}
	return out
}

// Latest devolve a última posição de cada usuário, para o mapa do admin.
func (h *LocationHandler) Latest(w http.ResponseWriter, r *http.Request) {
	reports, err := h.locations.LatestByUser(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal server error")
		return
	}

	writeJSON(w, http.StatusOK, toReportResponses(reports))
}

// Log devolve o histórico detalhado dos reports de localização, mais recentes
// primeiro, com o horário de cada leitura. Aceita ?userId= para filtrar um
// motorista e ?limit= (padrão 200, máximo 1000).
func (h *LocationHandler) Log(w http.ResponseWriter, r *http.Request) {
	var userID *uuid.UUID
	if raw := r.URL.Query().Get("userId"); raw != "" {
		id, err := uuid.Parse(raw)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid userId")
			return
		}
		userID = &id
	}

	limit := 200
	if raw := r.URL.Query().Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 {
			writeError(w, http.StatusBadRequest, "invalid limit")
			return
		}
		if n > 1000 {
			n = 1000
		}
		limit = n
	}

	reports, err := h.locations.History(r.Context(), userID, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal server error")
		return
	}

	writeJSON(w, http.StatusOK, toReportResponses(reports))
}
