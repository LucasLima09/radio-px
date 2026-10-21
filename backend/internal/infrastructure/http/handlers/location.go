package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/location"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
)

type LocationHandler struct {
	locations location.Repository
}

func NewLocationHandler(locations location.Repository) *LocationHandler {
	return &LocationHandler{locations: locations}
}

type reportLocationRequest struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

// Report persiste a posição atual do usuário. É chamado pelo beacon Android
// mesmo quando o usuário está fora de um canal, por isso o channel_id fica nil.
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

	loc, err := location.New(u.ID, nil, req.Lat, req.Lng)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid location")
		return
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
	ReportedAt time.Time `json:"reportedAt"`
}

// Latest devolve a última posição de cada usuário, para o mapa do admin.
func (h *LocationHandler) Latest(w http.ResponseWriter, r *http.Request) {
	reports, err := h.locations.LatestByUser(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal server error")
		return
	}

	out := make([]locationReportResponse, 0, len(reports))
	for _, rep := range reports {
		out = append(out, locationReportResponse{
			UserID:     rep.UserID,
			Username:   rep.Username,
			Lat:        rep.Latitude,
			Lng:        rep.Longitude,
			ReportedAt: rep.ReportedAt,
		})
	}
	writeJSON(w, http.StatusOK, out)
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

	out := make([]locationReportResponse, 0, len(reports))
	for _, rep := range reports {
		out = append(out, locationReportResponse{
			UserID:     rep.UserID,
			Username:   rep.Username,
			Lat:        rep.Latitude,
			Lng:        rep.Longitude,
			ReportedAt: rep.ReportedAt,
		})
	}
	writeJSON(w, http.StatusOK, out)
}