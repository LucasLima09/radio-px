package auth

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrInvalidRefresh     = errors.New("invalid refresh token")
	ErrExpiredRefresh     = errors.New("expired refresh token")
	ErrRevokedRefresh     = errors.New("revoked refresh token")
	ErrUsernameTaken      = errors.New("username already taken")
)

var dummyHash = func() []byte {
	h, _ := bcrypt.GenerateFromPassword([]byte("dummy-password-for-timing"), bcrypt.DefaultCost)
	return h
}()

type Service struct {
	users      user.Repository
	tokens     user.RefreshTokenRepository
	sign       TokenSigner
	refreshTTL time.Duration
}

type TokenSigner interface {
	GenerateAccessToken(userID uuid.UUID, username string) (string, time.Time, error)
	GenerateRefreshToken() (raw string, hash string, err error)
	HashToken(value string) string
}

func NewService(users user.Repository, tokens user.RefreshTokenRepository, sign TokenSigner, refreshTTL time.Duration) *Service {
	return &Service{
		users:      users,
		tokens:     tokens,
		sign:       sign,
		refreshTTL: refreshTTL,
	}
}

type RegisterInput struct {
	Username string
	Password string
}

type Tokens struct {
	AccessToken  string
	RefreshToken string
	ExpiresAt    time.Time
	User         user.Public
}

func (s *Service) Register(ctx context.Context, in RegisterInput) (user.Public, error) {
	if len(in.Password) < 6 {
		return user.Public{}, user.ErrWeakPassword
	}

	if _, err := s.users.FindByUsername(ctx, in.Username); err == nil {
		return user.Public{}, ErrUsernameTaken
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), bcrypt.DefaultCost)
	if err != nil {
		return user.Public{}, err
	}

	u, err := user.New(in.Username, string(hash))
	if err != nil {
		return user.Public{}, err
	}
	if err := s.users.Create(ctx, u); err != nil {
		return user.Public{}, err
	}
	return u.Public(), nil
}

func (s *Service) Login(ctx context.Context, username, password string) (*Tokens, error) {
	u, err := s.users.FindByUsername(ctx, username)
	if err != nil {
		if errors.Is(err, user.ErrNotFound) {
			_ = bcrypt.CompareHashAndPassword(dummyHash, []byte(password))
			return nil, ErrInvalidCredentials
		}
		return nil, err
	}
	if err := bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(password)); err != nil {
		return nil, ErrInvalidCredentials
	}
	return s.issueTokens(ctx, u)
}

func (s *Service) Refresh(ctx context.Context, raw string) (*Tokens, error) {
	hash := s.sign.HashToken(raw)
	rt, err := s.tokens.FindByHash(ctx, hash)
	if err != nil {
		return nil, ErrInvalidRefresh
	}
	if rt.RevokedAt != nil {
		return nil, ErrRevokedRefresh
	}
	if time.Now().UTC().After(rt.ExpiresAt) {
		return nil, ErrExpiredRefresh
	}

	u, err := s.users.FindByID(ctx, rt.UserID)
	if err != nil {
		return nil, err
	}

	if err := s.tokens.Revoke(ctx, rt.ID); err != nil {
		return nil, err
	}

	return s.issueTokens(ctx, u)
}

func (s *Service) Logout(ctx context.Context, raw string) error {
	hash := s.sign.HashToken(raw)
	rt, err := s.tokens.FindByHash(ctx, hash)
	if err != nil {
		return nil
	}
	return s.tokens.Revoke(ctx, rt.ID)
}

func (s *Service) issueTokens(ctx context.Context, u *user.User) (*Tokens, error) {
	access, expiresAt, err := s.sign.GenerateAccessToken(u.ID, u.Username)
	if err != nil {
		return nil, err
	}

	raw, hash, err := s.sign.GenerateRefreshToken()
	if err != nil {
		return nil, err
	}

	rt := user.NewRefreshToken(u.ID, hash, s.refreshTTL)
	if err := s.tokens.Create(ctx, rt); err != nil {
		return nil, err
	}

	return &Tokens{
		AccessToken:  access,
		RefreshToken: raw,
		ExpiresAt:    expiresAt,
		User:         u.Public(),
	}, nil
}
