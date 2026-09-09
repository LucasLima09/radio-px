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
)

type User struct {
	ID           uuid.UUID
	Username     string
	PasswordHash string
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
		CreatedAt:    now,
		UpdatedAt:    now,
	}, nil
}

type Public struct {
	ID       uuid.UUID `json:"id"`
	Username string    `json:"username"`
}

func (u *User) Public() Public {
	return Public{ID: u.ID, Username: u.Username}
}
