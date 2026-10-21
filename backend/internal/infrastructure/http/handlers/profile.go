package handlers

import (
	"bytes"
	"encoding/base64"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
)

const maxAvatarBytes = 256 * 1024

type profileRequest struct {
	Username *string `json:"username"`
	Avatar   *string `json:"avatar"`
}

func (h *UsersHandler) Profile(w http.ResponseWriter, r *http.Request) {
	u, ok := middleware.UserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "Sessão expirada")
		return
	}
	writeJSON(w, http.StatusOK, u.Public())
}

func (h *UsersHandler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	u, ok := middleware.UserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "Sessão expirada")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 400*1024)
	var req profileRequest
	if err := decodeJSON(w, r, &req); err != nil {
		return
	}
	if req.Username == nil && req.Avatar == nil {
		writeError(w, http.StatusBadRequest, "Nenhuma alteração informada")
		return
	}
	updated := *u
	if req.Username != nil {
		name := strings.TrimSpace(*req.Username)
		if utf8.RuneCountInString(name) < 3 || utf8.RuneCountInString(name) > 50 {
			writeError(w, http.StatusUnprocessableEntity, "O nome deve ter entre 3 e 50 caracteres")
			return
		}
		updated.Username = name
	}
	if req.Avatar != nil {
		if !validAvatar(*req.Avatar) {
			writeError(w, http.StatusUnprocessableEntity, "Use uma foto JPEG ou PNG de até 256 KB e 1024 pixels")
			return
		}
		updated.Avatar = *req.Avatar
	}
	updated.UpdatedAt = time.Now().UTC()
	if err := h.users.Update(r.Context(), &updated); err != nil {
		writeDomainError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, updated.Public())
}

func validAvatar(value string) bool {
	if value == "" {
		return true
	}
	header, encoded, ok := strings.Cut(value, ",")
	if !ok || (header != "data:image/jpeg;base64" && header != "data:image/png;base64") {
		return false
	}
	if len(encoded) > base64.StdEncoding.EncodedLen(maxAvatarBytes) {
		return false
	}
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil || len(data) > maxAvatarBytes {
		return false
	}
	config, format, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || config.Width < 1 || config.Height < 1 || config.Width > 1024 || config.Height > 1024 {
		return false
	}
	if header == "data:image/jpeg;base64" && format != "jpeg" {
		return false
	}
	if header == "data:image/png;base64" && format != "png" {
		return false
	}
	_, _, err = image.Decode(bytes.NewReader(data))
	return err == nil
}
