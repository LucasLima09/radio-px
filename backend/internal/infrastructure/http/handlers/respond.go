package handlers

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/lucas/radio-px-backend/internal/application/auth"
	domainchannel "github.com/lucas/radio-px-backend/internal/domain/channel"
	"github.com/lucas/radio-px-backend/internal/domain/user"
)

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func writeDomainError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, domainchannel.ErrInvalidLocation) || errors.Is(err, domainchannel.ErrInvalidRadius):
		writeError(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, user.ErrNotFound) || errors.Is(err, domainchannel.ErrNotFound):
		writeError(w, http.StatusNotFound, err.Error())
	case errors.Is(err, user.ErrInvalidUsername) ||
		errors.Is(err, user.ErrWeakPassword) ||
		errors.Is(err, domainchannel.ErrInvalidChannelName):
		writeError(w, http.StatusUnprocessableEntity, err.Error())
	case errors.Is(err, auth.ErrInvalidCredentials):
		writeError(w, http.StatusUnauthorized, err.Error())
	case errors.Is(err, auth.ErrInvalidRefresh):
		writeError(w, http.StatusBadRequest, "invalid refresh token")
	case errors.Is(err, auth.ErrExpiredRefresh):
		writeError(w, http.StatusUnauthorized, "refresh token expired")
	case errors.Is(err, auth.ErrRevokedRefresh):
		writeError(w, http.StatusUnauthorized, "refresh token revoked")
	case errors.Is(err, auth.ErrUsernameTaken):
		writeError(w, http.StatusConflict, err.Error())
	default:
		writeError(w, http.StatusInternalServerError, "internal server error")
	}
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(dst); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return err
	}
	return nil
}
