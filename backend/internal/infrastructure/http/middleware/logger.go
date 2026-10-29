package middleware

import (
	"log/slog"
	"net/http"
	"net/url"
	"time"

	chimw "github.com/go-chi/chi/v5/middleware"
)

// sensitiveQueryParams are redacted before a URL is logged. The WebSocket
// handshake carries the access token in ?token= because browsers cannot set
// headers on it.
var sensitiveQueryParams = []string{"token", "access_token", "refresh_token"}

// RequestLogger logs each request with slog, like chi's Logger, but never
// writes credentials found in the query string.
func RequestLogger(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			ww := chimw.NewWrapResponseWriter(w, r.ProtoMajor)
			defer func() {
				logger.Info("http request",
					"method", r.Method,
					"path", RedactURL(r.URL),
					"status", ww.Status(),
					"bytes", ww.BytesWritten(),
					"duration", time.Since(start),
					"remote", r.RemoteAddr,
					"request_id", chimw.GetReqID(r.Context()),
				)
			}()
			next.ServeHTTP(ww, r)
		})
	}
}

// RedactURL returns the path and query of u with sensitive parameters masked.
func RedactURL(u *url.URL) string {
	query := u.Query()
	redacted := false
	for _, key := range sensitiveQueryParams {
		if query.Has(key) {
			query.Set(key, "REDACTED")
			redacted = true
		}
	}
	if !redacted {
		return u.RequestURI()
	}
	return u.Path + "?" + query.Encode()
}
