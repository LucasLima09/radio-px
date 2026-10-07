package handlers

import (
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
)

type UsersHandler struct {
	users user.Repository
}

func NewUsersHandler(users user.Repository) *UsersHandler {
	return &UsersHandler{users: users}
}

// List devolve todos os usuários cadastrados, para o painel do admin.
func (h *UsersHandler) List(w http.ResponseWriter, r *http.Request) {
	users, err := h.users.List(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal server error")
		return
	}

	out := make([]user.Public, 0, len(users))
	for _, u := range users {
		out = append(out, u.Public())
	}
	writeJSON(w, http.StatusOK, out)
}

type updateUserRequest struct {
	Username *string `json:"username,omitempty"`
	Role     *string `json:"role,omitempty"`
}

// Update edita username e/ou role de um usuário. A role só entra em vigor nos
// tokens novos (refresh ou novo login).
func (h *UsersHandler) Update(w http.ResponseWriter, r *http.Request) {
	userID, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid user id")
		return
	}

	var req updateUserRequest
	if err := decodeJSON(w, r, &req); err != nil {
		return
	}
	if (req.Username == nil || strings.TrimSpace(*req.Username) == "") &&
		(req.Role == nil) {
		writeError(w, http.StatusBadRequest, "nothing to update")
		return
	}

	u, err := h.users.FindByID(r.Context(), userID)
	if err != nil {
		writeDomainError(w, err)
		return
	}

	if req.Username != nil {
		u.Username = strings.TrimSpace(*req.Username)
		if len(u.Username) < 3 {
			writeDomainError(w, user.ErrInvalidUsername)
			return
		}
	}
	if req.Role != nil {
		if !user.ValidRole(*req.Role) {
			writeError(w, http.StatusUnprocessableEntity, user.ErrInvalidRole.Error())
			return
		}
		u.Role = *req.Role
	}
	u.UpdatedAt = time.Now().UTC()

	if err := h.users.Update(r.Context(), u); err != nil {
		writeDomainError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, u.Public())
}

// Delete remove um usuário e todos os dados relacionados (canais, adesões,
// tokens e posições via ON DELETE CASCADE). O admin não pode excluir a si mesmo.
func (h *UsersHandler) Delete(w http.ResponseWriter, r *http.Request) {
	userID, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid user id")
		return
	}

	me, ok := middleware.UserFromContext(r.Context())
	if ok && me.ID == userID {
		writeError(w, http.StatusBadRequest, "cannot delete your own account")
		return
	}

	if err := h.users.Delete(r.Context(), userID); err != nil {
		writeDomainError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}