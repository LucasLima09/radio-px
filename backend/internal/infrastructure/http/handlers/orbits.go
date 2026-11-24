package handlers

import (
	"crypto/ed25519"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/orbit"
)

// OrbitHandler expõe os Orbits descobertos: o painel renomeia e bloqueia; os
// apps baixam a chave pública que confere a assinatura dos sinais.
type OrbitHandler struct {
	orbits orbit.Repository
	key    ed25519.PublicKey
}

func NewOrbitHandler(orbits orbit.Repository, key ed25519.PublicKey) *OrbitHandler {
	return &OrbitHandler{orbits: orbits, key: key}
}

type appOrbitResponse struct {
	Name       string `json:"name"`
	Identifier string `json:"identifier"`
}

type appOrbitsResponse struct {
	// PublicKey em base64; vazia se o servidor não tem ORBIT_PUBLIC_KEY.
	PublicKey []byte             `json:"publicKey"`
	Orbits    []appOrbitResponse `json:"orbits"`
}

// Config devolve ao app a chave pública e os nomes dos Orbits conhecidos. Os
// nomes só servem para exibição: um Orbit fora da lista também é aceito.
func (h *OrbitHandler) Config(w http.ResponseWriter, r *http.Request) {
	list, err := h.orbits.List(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal server error")
		return
	}
	out := appOrbitsResponse{PublicKey: h.key, Orbits: make([]appOrbitResponse, 0, len(list))}
	for _, o := range list {
		out.Orbits = append(out.Orbits, appOrbitResponse{Name: o.Name, Identifier: o.Identifier})
	}
	writeJSON(w, http.StatusOK, out)
}

// List devolve todos os Orbits, ativos ou não, para o painel.
func (h *OrbitHandler) List(w http.ResponseWriter, r *http.Request) {
	list, err := h.orbits.List(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal server error")
		return
	}
	writeJSON(w, http.StatusOK, list)
}

type updateOrbitRequest struct {
	Name   *string `json:"name"`
	Active *bool   `json:"active"`
}

func (h *OrbitHandler) Update(w http.ResponseWriter, r *http.Request) {
	id, ok := orbitIDParam(w, r)
	if !ok {
		return
	}
	var req updateOrbitRequest
	if err := decodeJSON(w, r, &req); err != nil {
		return
	}
	o, err := h.orbits.Get(r.Context(), id)
	if err != nil {
		writeOrbitError(w, err)
		return
	}
	if req.Name != nil {
		if err := o.Rename(*req.Name); err != nil {
			writeOrbitError(w, err)
			return
		}
	}
	if req.Active != nil {
		o.Active = *req.Active
	}
	if err := h.orbits.Update(r.Context(), o); err != nil {
		writeOrbitError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, o)
}

func (h *OrbitHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id, ok := orbitIDParam(w, r)
	if !ok {
		return
	}
	if err := h.orbits.Delete(r.Context(), id); err != nil {
		writeOrbitError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func orbitIDParam(w http.ResponseWriter, r *http.Request) (uuid.UUID, bool) {
	id, err := uuid.Parse(chi.URLParam(r, "orbitID"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "Orbit inválido.")
		return uuid.Nil, false
	}
	return id, true
}

func writeOrbitError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, orbit.ErrNotFound):
		writeError(w, http.StatusNotFound, "Orbit não encontrado.")
	case errors.Is(err, orbit.ErrInvalidName):
		writeError(w, http.StatusUnprocessableEntity, "Informe um nome de até 64 caracteres.")
	default:
		writeError(w, http.StatusInternalServerError, "internal server error")
	}
}
