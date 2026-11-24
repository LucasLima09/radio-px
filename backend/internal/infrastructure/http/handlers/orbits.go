package handlers

import (
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/orbit"
)

// OrbitHandler expõe o cadastro de Orbits: o painel admin mantém a lista e os
// apps a baixam para saber quais dispositivos Bluetooth reconhecer.
type OrbitHandler struct {
	orbits orbit.Repository
}

func NewOrbitHandler(orbits orbit.Repository) *OrbitHandler {
	return &OrbitHandler{orbits: orbits}
}

type appOrbitResponse struct {
	ID         uuid.UUID `json:"id"`
	Name       string    `json:"name"`
	Identifier string    `json:"identifier"`
}

// ListActive devolve os Orbits ativos para o app.
func (h *OrbitHandler) ListActive(w http.ResponseWriter, r *http.Request) {
	list, err := h.orbits.List(r.Context(), true)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal server error")
		return
	}
	out := make([]appOrbitResponse, 0, len(list))
	for _, o := range list {
		out = append(out, appOrbitResponse{ID: o.ID, Name: o.Name, Identifier: o.Identifier})
	}
	writeJSON(w, http.StatusOK, out)
}

// List devolve todos os Orbits, ativos ou não, para o painel.
func (h *OrbitHandler) List(w http.ResponseWriter, r *http.Request) {
	list, err := h.orbits.List(r.Context(), false)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal server error")
		return
	}
	writeJSON(w, http.StatusOK, list)
}

type createOrbitRequest struct {
	Name       string `json:"name"`
	Identifier string `json:"identifier"`
}

func (h *OrbitHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req createOrbitRequest
	if err := decodeJSON(w, r, &req); err != nil {
		return
	}
	o, err := orbit.New(req.Name, req.Identifier)
	if err != nil {
		writeOrbitError(w, err)
		return
	}
	if err := h.orbits.Create(r.Context(), o); err != nil {
		writeOrbitError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, o)
}

type updateOrbitRequest struct {
	Name       *string `json:"name"`
	Identifier *string `json:"identifier"`
	Active     *bool   `json:"active"`
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
	name, identifier := o.Name, o.Identifier
	if req.Name != nil {
		name = *req.Name
	}
	if req.Identifier != nil {
		identifier = *req.Identifier
	}
	if err := o.Rename(name, identifier); err != nil {
		writeOrbitError(w, err)
		return
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
	case errors.Is(err, orbit.ErrDuplicate):
		writeError(w, http.StatusConflict, "Já existe um Orbit com esse identificador.")
	case errors.Is(err, orbit.ErrInvalidName):
		writeError(w, http.StatusUnprocessableEntity, "Informe um nome de até 64 caracteres.")
	case errors.Is(err, orbit.ErrInvalidIdentifier):
		writeError(w, http.StatusUnprocessableEntity, "Informe o identificador Bluetooth (até 64 caracteres, sem quebras de linha).")
	default:
		writeError(w, http.StatusInternalServerError, "internal server error")
	}
}
