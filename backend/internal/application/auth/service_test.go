package auth

import (
	"context"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	appjwt "github.com/lucas/radio-px-backend/internal/infrastructure/auth/jwt"
)

type memoryUserRepo struct {
	mu     sync.Mutex
	byID   map[uuid.UUID]*user.User
	byName map[string]*user.User
}

func newMemoryUserRepo() *memoryUserRepo {
	return &memoryUserRepo{
		byID:   make(map[uuid.UUID]*user.User),
		byName: make(map[string]*user.User),
	}
}

func (r *memoryUserRepo) Create(_ context.Context, u *user.User) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.byID[u.ID] = u
	r.byName[u.Username] = u
	return nil
}

func (r *memoryUserRepo) FindByUsername(_ context.Context, username string) (*user.User, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	u, ok := r.byName[username]
	if !ok {
		return nil, user.ErrNotFound
	}
	return u, nil
}

func (r *memoryUserRepo) FindByID(_ context.Context, id uuid.UUID) (*user.User, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	u, ok := r.byID[id]
	if !ok {
		return nil, user.ErrNotFound
	}
	return u, nil
}

type memoryTokenRepo struct {
	mu     sync.Mutex
	tokens map[string]*user.RefreshToken
}

func newMemoryTokenRepo() *memoryTokenRepo {
	return &memoryTokenRepo{tokens: make(map[string]*user.RefreshToken)}
}

func (r *memoryTokenRepo) Create(_ context.Context, t *user.RefreshToken) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.tokens[t.TokenHash] = t
	return nil
}

func (r *memoryTokenRepo) FindByHash(_ context.Context, hash string) (*user.RefreshToken, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	t, ok := r.tokens[hash]
	if !ok {
		return nil, user.ErrNotFound
	}
	return t, nil
}

func (r *memoryTokenRepo) Revoke(_ context.Context, id uuid.UUID) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, t := range r.tokens {
		if t.ID == id {
			now := time.Now().UTC()
			t.RevokedAt = &now
			return nil
		}
	}
	return nil
}

func newTestService(t *testing.T) *Service {
	t.Helper()
	signer := appjwt.New("test-secret-that-is-long-enough-1234", "radio-px-test", 15*time.Minute)
	return NewService(newMemoryUserRepo(), newMemoryTokenRepo(), signer, 7*24*time.Hour)
}

func TestRegisterAndLogin(t *testing.T) {
	ctx := context.Background()
	svc := newTestService(t)

	created, err := svc.Register(ctx, RegisterInput{Username: "lucas", Password: "secret123"})
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	if created.Username != "lucas" {
		t.Fatalf("expected username lucas, got %s", created.Username)
	}

	tokens, err := svc.Login(ctx, "lucas", "secret123")
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if tokens.AccessToken == "" || tokens.RefreshToken == "" {
		t.Fatal("expected access and refresh tokens")
	}
	if tokens.User.Username != "lucas" {
		t.Fatalf("unexpected user %v", tokens.User)
	}
}

func TestLoginWrongPassword(t *testing.T) {
	ctx := context.Background()
	svc := newTestService(t)

	if _, err := svc.Register(ctx, RegisterInput{Username: "lucas", Password: "secret123"}); err != nil {
		t.Fatalf("register: %v", err)
	}

	if _, err := svc.Login(ctx, "lucas", "wrong-password"); err != ErrInvalidCredentials {
		t.Fatalf("expected ErrInvalidCredentials, got %v", err)
	}
}

func TestRegisterDuplicateUsername(t *testing.T) {
	ctx := context.Background()
	svc := newTestService(t)

	if _, err := svc.Register(ctx, RegisterInput{Username: "lucas", Password: "secret123"}); err != nil {
		t.Fatalf("register: %v", err)
	}
	if _, err := svc.Register(ctx, RegisterInput{Username: "lucas", Password: "secret123"}); err != ErrUsernameTaken {
		t.Fatalf("expected ErrUsernameTaken, got %v", err)
	}
}

func TestRefreshRotationAndRevocation(t *testing.T) {
	ctx := context.Background()
	svc := newTestService(t)

	if _, err := svc.Register(ctx, RegisterInput{Username: "lucas", Password: "secret123"}); err != nil {
		t.Fatalf("register: %v", err)
	}
	first, err := svc.Login(ctx, "lucas", "secret123")
	if err != nil {
		t.Fatalf("login: %v", err)
	}

	second, err := svc.Refresh(ctx, first.RefreshToken)
	if err != nil {
		t.Fatalf("refresh: %v", err)
	}
	if second.RefreshToken == first.RefreshToken {
		t.Fatal("refresh must rotate the refresh token")
	}

	// Old token must be revoked after rotation.
	if _, err := svc.Refresh(ctx, first.RefreshToken); err != ErrRevokedRefresh {
		t.Fatalf("expected ErrRevokedRefresh for old token, got %v", err)
	}

	// The new token still works.
	third, err := svc.Refresh(ctx, second.RefreshToken)
	if err != nil {
		t.Fatalf("refresh with rotated token: %v", err)
	}
	if third.RefreshToken == "" {
		t.Fatal("expected a new refresh token")
	}
}

func TestLogoutRevokes(t *testing.T) {
	ctx := context.Background()
	svc := newTestService(t)

	if _, err := svc.Register(ctx, RegisterInput{Username: "lucas", Password: "secret123"}); err != nil {
		t.Fatalf("register: %v", err)
	}
	tokens, err := svc.Login(ctx, "lucas", "secret123")
	if err != nil {
		t.Fatalf("login: %v", err)
	}

	if err := svc.Logout(ctx, tokens.RefreshToken); err != nil {
		t.Fatalf("logout: %v", err)
	}

	if _, err := svc.Refresh(ctx, tokens.RefreshToken); err != ErrRevokedRefresh {
		t.Fatalf("expected ErrRevokedRefresh after logout, got %v", err)
	}
}

func TestRegisterWeakPassword(t *testing.T) {
	ctx := context.Background()
	svc := newTestService(t)

	if _, err := svc.Register(ctx, RegisterInput{Username: "lucas", Password: "123"}); err != user.ErrWeakPassword {
		t.Fatalf("expected ErrWeakPassword, got %v", err)
	}
}

func TestGeneratedAccessTokenCarriesUser(t *testing.T) {
	ctx := context.Background()
	svc := newTestService(t)

	if _, err := svc.Register(ctx, RegisterInput{Username: "lucas", Password: "secret123"}); err != nil {
		t.Fatalf("register: %v", err)
	}
	tokens, err := svc.Login(ctx, "lucas", "secret123")
	if err != nil {
		t.Fatalf("login: %v", err)
	}

	// Validate the access token by parsing it with the same manager used to sign.
	signer := appjwt.New("test-secret-that-is-long-enough-1234", "radio-px-test", 15*time.Minute)
	claims, err := signer.ParseAccessToken(tokens.AccessToken)
	if err != nil {
		t.Fatalf("parse access token: %v", err)
	}
	if claims.UserID == uuid.Nil {
		t.Fatal("access token must carry the user id")
	}
	if !strings.EqualFold(claims.Username, "lucas") {
		t.Fatalf("unexpected username %q", claims.Username)
	}
}
