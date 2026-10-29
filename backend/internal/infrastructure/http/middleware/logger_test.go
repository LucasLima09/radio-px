package middleware

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRequestLoggerRedactsToken(t *testing.T) {
	var out bytes.Buffer
	logger := slog.New(slog.NewTextHandler(&out, nil))
	handler := RequestLogger(logger)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// The handler itself still sees the real token.
		if r.URL.Query().Get("token") != "secret-jwt" {
			t.Errorf("handler lost the token: %q", r.URL.RawQuery)
		}
		w.WriteHeader(http.StatusTeapot)
	}))

	req := httptest.NewRequest("GET", "/ws?token=secret-jwt&channel_id=abc", nil)
	handler.ServeHTTP(httptest.NewRecorder(), req)

	line := out.String()
	if strings.Contains(line, "secret-jwt") {
		t.Fatalf("token leaked into log: %s", line)
	}
	if !strings.Contains(line, "channel_id=abc") || !strings.Contains(line, "status=418") {
		t.Fatalf("log misses request details: %s", line)
	}
}
