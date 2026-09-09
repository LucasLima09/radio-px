package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/lucas/radio-px-backend/internal/domain/user"
	"github.com/lucas/radio-px-backend/internal/infrastructure/auth/jwt"
)

type ctxKey string

const userKey ctxKey = "user"

func UserFromContext(ctx context.Context) (*user.User, bool) {
	u, ok := ctx.Value(userKey).(*user.User)
	return u, ok
}

func WithUser(ctx context.Context, u *user.User) context.Context {
	return context.WithValue(ctx, userKey, u)
}

func Authenticate(tokenManager *jwt.Manager, users user.Repository) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if header == "" {
				writeUnauthorized(w)
				return
			}

			parts := strings.SplitN(header, " ", 2)
			if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
				writeUnauthorized(w)
				return
			}

			claims, err := tokenManager.ParseAccessToken(parts[1])
			if err != nil {
				writeUnauthorized(w)
				return
			}

			u, err := users.FindByID(r.Context(), claims.UserID)
			if err != nil {
				writeUnauthorized(w)
				return
			}

			next.ServeHTTP(w, r.WithContext(WithUser(r.Context(), u)))
		})
	}
}

func writeUnauthorized(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	_, _ = w.Write([]byte(`{"error":"unauthorized"}`))
}
