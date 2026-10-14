package user

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrInvalidUsername = errors.New("username must have at least 3 characters")
	ErrWeakPassword    = errors.New("password must have at least 6 characters")
	ErrUsernameTaken   = errors.New("username already taken")
	ErrInvalidRole     = errors.New("invalid role")
)

// Roles. Todos os usuários nascem como user; admin é promovido manualmente no
// banco e refletido no token de acesso.
const (
	RoleUser  = "user"
	RoleAdmin = "admin"
)

type User struct {
	ID           uuid.UUID
	Username     string
	PasswordHash string
	Role         string
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

func New(username, passwordHash string) (*User, error) {
	username = strings.TrimSpace(username)

	if len(username) < 3 {
		return nil, ErrInvalidUsername
	}
	if len(passwordHash) == 0 {
		return nil, ErrWeakPassword
	}

	now := time.Now().UTC()
	return &User{
		ID:           uuid.New(),
		Username:     username,
		PasswordHash: passwordHash,
		Role:         RoleUser,
		CreatedAt:    now,
		UpdatedAt:    now,
	}, nil
}

type Public struct {
	ID       uuid.UUID `json:"id"`
	Username string    `json:"username"`
	Role     string    `json:"role"`
	CreatedAt time.Time `json:"createdAt"`
}

func (u *User) Public() Public {
	return Public{ID: u.ID, Username: u.Username, Role: u.Role, CreatedAt: u.CreatedAt}
}

// ValidRole reporta se role é uma das roles aceitas.
func ValidRole(role string) bool {
	return role == RoleUser || role == RoleAdmin
}
