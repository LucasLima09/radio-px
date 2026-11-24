package handlers

import (
	"crypto/ed25519"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/location"
	"github.com/lucas/radio-px-backend/internal/domain/orbit"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
)

type LocationHandler struct {
	locations location.Repository
	orbits    orbit.Repository
	orbitKey  ed25519.PublicKey
}

func NewLocationHandler(locations location.Repository, orbits orbit.Repository, orbitKey ed25519.PublicKey) *LocationHandler {
	return &LocationHandler{locations: locations, orbits: orbits, orbitKey: orbitKey}
}

type reportLocationRequest struct {
	// ID gerado pelo app para o encontro. Torna o envio idempotente: o app
	// reenvia o que ficou na fila sem saber se a resposta anterior se perdeu.
	ID *uuid.UUID `json:"id"`
	// Signal são os 84 bytes assinados que o Orbit transmitiu, em base64.
	Signal []byte `json:"signal"`
	RSSI   *int   `json:"rssi"`
	// At é a hora em que o app ouviu o sinal (RFC 3339). Sem ela, vale a hora
	// de chegada.
	At *time.Time `json:"at"`
}

// Report persiste o sinal de um Orbit repassado pelo app. Posição e hora vêm
// do sinal; a assinatura é conferida aqui mesmo que o app já tenha conferido.
// Um Orbit novo é criado sozinho; um desativado no painel é recusado. Reenviar
// o mesmo id responde 204 sem gravar de novo.
func (h *LocationHandler) Report(w http.ResponseWriter, r *http.Request) {
	u, ok := middleware.UserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if len(h.orbitKey) == 0 {
		writeError(w, http.StatusServiceUnavailable, "Servidor sem a chave dos Orbits (ORBIT_PUBLIC_KEY).")
		return
	}

	var req reportLocationRequest
	if err := decodeJSON(w, r, &req); err != nil {
		return
	}

	signal, err := orbit.OpenSignal(req.Signal, h.orbitKey)
	if errors.Is(err, orbit.ErrInvalidSignal) {
		writeError(w, http.StatusBadRequest, "Sinal de Orbit inválido.")
		return
	}
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, "Assinatura do Orbit inválida.")
		return
	}

	var at time.Time
	if req.At != nil {
		at = *req.At
	}
	err = location.ValidateEncounter(signal, req.RSSI, at)
	if errors.Is(err, location.ErrInvalidTime) {
		writeError(w, http.StatusBadRequest, "Hora do sinal fora do limite.")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "Localização inválida.")
		return
	}

	o, err := h.orbits.Ensure(r.Context(), signal.Identifier())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal server error")
		return
	}
	if !o.Active {
		writeError(w, http.StatusUnprocessableEntity, "Orbit desativado no painel.")
		return
	}

	loc, err := location.NewEncounter(u.ID, signal, o, req.RSSI, at)
	if err != nil {
		writeError(w, http.StatusBadRequest, "Sinal de Orbit inválido.")
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
