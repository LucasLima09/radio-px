package middleware

import (
	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRequireAdminMergedAuthorization(t *testing.T) {
	configured := uuid.New()
	for _, tc := range []struct {
		name    string
		account *user.User
		status  int
	}{
		{"anonymous", nil, 401},
		{"regular user", &user.User{ID: uuid.New()}, 403},
		{"configured admin", &user.User{ID: configured}, 204},
		{"role admin", &user.User{ID: uuid.New(), Role: user.RoleAdmin}, 204},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest("GET", "/", nil)
			if tc.account != nil {
				req = req.WithContext(WithUser(req.Context(), tc.account))
			}
			res := httptest.NewRecorder()
			RequireAdmin([]string{configured.String()})(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) })).ServeHTTP(res, req)
			if res.Code != tc.status {
				t.Fatalf("got %d, want %d", res.Code, tc.status)
			}
		})
	}
}
