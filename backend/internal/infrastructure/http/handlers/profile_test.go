package handlers

import (
	"bytes"
	"context"
	"encoding/base64"
	"image"
	"image/png"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
)

type profileRepo struct {
	user.Repository
	saved *user.User
	err   error
}

func (r *profileRepo) Update(_ context.Context, u *user.User) error {
	if r.err != nil {
		return r.err
	}
	copy := *u
	r.saved = &copy
	return nil
}

func TestUpdateProfile(t *testing.T) {
	for _, tc := range []struct {
		name, body    string
		authenticated bool
		status        int
	}{
		{"no session", `{"username":"new.name"}`, false, http.StatusUnauthorized},
		{"save name and remove photo", `{"username":" new.name ","avatar":""}`, true, http.StatusOK},
		{"invalid name", `{"username":"a"}`, true, http.StatusUnprocessableEntity},
		{"username with spaces", `{"username":"New name"}`, true, http.StatusUnprocessableEntity},
		{"invalid first name", `{"firstName":"Lucas1"}`, true, http.StatusUnprocessableEntity},
		{"invalid last name", `{"lastName":"Lima!"}`, true, http.StatusUnprocessableEntity},
		{"invalid photo", `{"avatar":"data:image/png;base64,YWJj"}`, true, http.StatusUnprocessableEntity},
		{"cannot promote self", `{"role":"admin"}`, true, http.StatusBadRequest},
		{"empty update", `{}`, true, http.StatusBadRequest},
		{"invalid plate", `{"vehiclePlate":"AB-12"}`, true, http.StatusUnprocessableEntity},
		{"invalid phone", `{"phone":"1234"}`, true, http.StatusUnprocessableEntity},
	} {
		t.Run(tc.name, func(t *testing.T) {
			original := &user.User{ID: uuid.New(), Username: "Original", Role: user.RoleUser, PasswordHash: "secret hash", Avatar: "old photo"}
			repo := &profileRepo{}
			req := httptest.NewRequest(http.MethodPatch, "/api/v1/profile", strings.NewReader(tc.body))
			if tc.authenticated {
				req = req.WithContext(middleware.WithUser(req.Context(), original))
			}
			response := httptest.NewRecorder()
			NewUsersHandler(repo).UpdateProfile(response, req)
			if response.Code != tc.status {
				t.Fatalf("status %d: %s", response.Code, response.Body.String())
			}
			if original.Username != "Original" || original.Avatar != "old photo" {
				t.Fatal("mutated authenticated user")
			}
			if tc.status == http.StatusOK {
				if repo.saved == nil || repo.saved.ID != original.ID || repo.saved.Username != "new.name" || repo.saved.Avatar != "" || repo.saved.Role != user.RoleUser || repo.saved.PasswordHash != "secret hash" {
					t.Fatal("incorrect saved profile")
				}
				if strings.Contains(response.Body.String(), "secret hash") {
					t.Fatal("password exposed")
				}
			} else if repo.saved != nil {
				t.Fatal("saved invalid request")
			}
		})
	}
}

func TestUpdateProfileContact(t *testing.T) {
	original := &user.User{ID: uuid.New(), Username: "Original", Role: user.RoleUser}
	repo := &profileRepo{}
	req := httptest.NewRequest(http.MethodPatch, "/api/v1/profile",
		strings.NewReader(`{"vehiclePlate":"abc-1d23","phone":"(11) 98765-4321"}`))
	req = req.WithContext(middleware.WithUser(req.Context(), original))
	response := httptest.NewRecorder()
	NewUsersHandler(repo).UpdateProfile(response, req)
	if response.Code != http.StatusOK {
		t.Fatalf("status %d: %s", response.Code, response.Body.String())
	}
	if repo.saved.VehiclePlate != "ABC1D23" || repo.saved.Phone != "11987654321" || repo.saved.Username != "Original" {
		t.Fatalf("incorrect saved contact: %+v", repo.saved)
	}
	if !strings.Contains(response.Body.String(), `"vehiclePlate":"ABC1D23"`) {
		t.Fatalf("plate missing from response: %s", response.Body.String())
	}
}

func TestUpdateProfileNames(t *testing.T) {
	// Conta antiga com espaço no usuário: reenviar o mesmo nome continua
	// funcionando.
	original := &user.User{ID: uuid.New(), Username: "Nome Antigo", Role: user.RoleUser}
	repo := &profileRepo{}
	req := httptest.NewRequest(http.MethodPatch, "/api/v1/profile",
		strings.NewReader(`{"username":"Nome Antigo","firstName":" Lucas ","lastName":"Lima"}`))
	req = req.WithContext(middleware.WithUser(req.Context(), original))
	response := httptest.NewRecorder()
	NewUsersHandler(repo).UpdateProfile(response, req)
	if response.Code != http.StatusOK {
		t.Fatalf("status %d: %s", response.Code, response.Body.String())
	}
	if repo.saved.Username != "Nome Antigo" || repo.saved.FirstName != "Lucas" || repo.saved.LastName != "Lima" {
		t.Fatalf("incorrect saved names: %+v", repo.saved)
	}
	if !strings.Contains(response.Body.String(), `"firstName":"Lucas"`) {
		t.Fatalf("first name missing from response: %s", response.Body.String())
	}
}

func TestProfileNameConflict(t *testing.T) {
	repo := &profileRepo{err: user.ErrUsernameTaken}
	u := &user.User{ID: uuid.New(), Username: "Original"}
	r := httptest.NewRequest(http.MethodPatch, "/profile", strings.NewReader(`{"username":"Taken"}`))
	r = r.WithContext(middleware.WithUser(r.Context(), u))
	w := httptest.NewRecorder()
	NewUsersHandler(repo).UpdateProfile(w, r)
	if w.Code != http.StatusConflict || u.Username != "Original" {
		t.Fatalf("conflict handled incorrectly: %d", w.Code)
	}
}

func TestValidAvatar(t *testing.T) {
	var data bytes.Buffer
	if err := png.Encode(&data, image.NewRGBA(image.Rect(0, 0, 8, 8))); err != nil {
		t.Fatal(err)
	}
	encoded := base64.StdEncoding.EncodeToString(data.Bytes())
	if !validAvatar("data:image/png;base64,"+encoded) || !validAvatar("") {
		t.Fatal("valid avatar rejected")
	}
	for _, invalid := range []string{
		"data:image/jpeg;base64," + encoded,
		"data:image/svg+xml;base64," + encoded,
		"data:image/png;base64,broken",
		"data:image/png;base64," + strings.Repeat("a", 400*1024),
	} {
		if validAvatar(invalid) {
			t.Fatal("invalid avatar accepted")
		}
	}
	data.Reset()
	if err := png.Encode(&data, image.NewRGBA(image.Rect(0, 0, 1025, 1))); err != nil {
		t.Fatal(err)
	}
	if validAvatar("data:image/png;base64," + base64.StdEncoding.EncodeToString(data.Bytes())) {
		t.Fatal("oversized dimensions accepted")
	}
}
