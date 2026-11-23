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

	"github.com/lucas/radio-px-backend/internal/domain/user"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
)

const maxAvatarBytes = 256 * 1024

type profileRequest struct {
	Username     *string `json:"username"`
	FirstName    *string `json:"firstName"`
	LastName     *string `json:"lastName"`
	Avatar       *string `json:"avatar"`
	VehiclePlate *string `json:"vehiclePlate"`
	Phone        *string `json:"phone"`
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
	if req.Username == nil && req.FirstName == nil && req.LastName == nil &&
		req.Avatar == nil && req.VehiclePlate == nil && req.Phone == nil {
		writeError(w, http.StatusBadRequest, "Nenhuma alteração informada")
		return
	}
	updated := *u
	if req.Username != nil {
		name := strings.TrimSpace(*req.Username)
		// Contas antigas podem ter um nome fora da regra atual; só um nome
		// novo precisa segui-la.
		if name != u.Username && !user.ValidUsername(name) {
			writeError(w, http.StatusUnprocessableEntity, "O usuário deve ter de 3 a 30 caracteres, sem espaços: letras, números, ponto, hífen ou sublinhado")
			return
		}
		updated.Username = name
	}
	if req.FirstName != nil {
		name, err := user.NormalizeFirstName(*req.FirstName)
		if err != nil {
			writeError(w, http.StatusUnprocessableEntity, "Primeiro nome inválido. Use apenas letras, até 50 caracteres")
			return
		}
		updated.FirstName = name
	}
	if req.LastName != nil {
		name, err := user.NormalizeLastName(*req.LastName)
		if err != nil {
			writeError(w, http.StatusUnprocessableEntity, "Sobrenome inválido. Use apenas letras, até 50 caracteres")
			return
		}
		updated.LastName = name
	}
	if req.Avatar != nil {
		if !validAvatar(*req.Avatar) {
			writeError(w, http.StatusUnprocessableEntity, "Use uma foto JPEG ou PNG de até 256 KB e 1024 pixels")
			return
		}
		updated.Avatar = *req.Avatar
	}
	if req.VehiclePlate != nil {
		plate, err := user.NormalizePlate(*req.VehiclePlate)
		if err != nil {
			writeError(w, http.StatusUnprocessableEntity, "Placa inválida. Use o padrão Mercosul: ABC1D23")
			return
		}
		updated.VehiclePlate = plate
	}
	if req.Phone != nil {
		phone, err := user.NormalizePhone(*req.Phone)
		if err != nil {
			writeError(w, http.StatusUnprocessableEntity, "Telefone inválido. Informe DDD e número (celular começa com 9)")
			return
		}
		updated.Phone = phone
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
