package middleware

import (
	"net/http"

	"github.com/google/uuid"
)

func RequireAdmin(ids []string) func(http.Handler) http.Handler {
	allowed := make(map[uuid.UUID]bool, len(ids))
	for _, value := range ids {
		if id, err := uuid.Parse(value); err == nil {
			allowed[id] = true
		}
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Cache-Control", "no-store")
			u, ok := UserFromContext(r.Context())
			if !ok {
				writeUnauthorized(w)
				return
			}
			if !allowed[u.ID] {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusForbidden)
				_, _ = w.Write([]byte(`{"error":"Acesso restrito a administradores."}`))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
