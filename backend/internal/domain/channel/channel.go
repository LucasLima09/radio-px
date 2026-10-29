package channel

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrInvalidChannelName = errors.New("channel name must have at least 1 character")
	ErrAlreadyMember      = errors.New("user is already a member of this channel")
	ErrNotMember          = errors.New("user is not a member of this channel")
	ErrPasswordRequired   = errors.New("channel password required")
	ErrWrongPassword      = errors.New("invalid channel password")
	ErrWeakPassword       = errors.New("channel password must have between 4 and 72 characters")
)

const (
	minPasswordLen = 4
	// bcrypt ignores everything past 72 bytes.
	maxPasswordLen = 72
)

type Channel struct {
	ID        uuid.UUID
	OwnerID   uuid.UUID
	Name      string
	IsPrivate bool
	// PasswordHash is the bcrypt hash a non-member must match to join a
	// private channel. Empty for public channels.
	PasswordHash string
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// ValidatePassword checks the plain password chosen for a private channel.
func ValidatePassword(password string) error {
	if len(password) < minPasswordLen || len(password) > maxPasswordLen {
		return ErrWeakPassword
	}
	return nil
}

// New builds a channel. passwordHash must be set for private channels and is
// ignored for public ones.
func New(ownerID uuid.UUID, name string, isPrivate bool, passwordHash string) (*Channel, error) {
	name = strings.TrimSpace(name)
	if len(name) == 0 {
		return nil, ErrInvalidChannelName
	}
	if !isPrivate {
		passwordHash = ""
	} else if passwordHash == "" {
		return nil, ErrPasswordRequired
	}

	now := time.Now().UTC()
	return &Channel{
		ID:           uuid.New(),
		OwnerID:      ownerID,
		Name:         name,
		IsPrivate:    isPrivate,
		PasswordHash: passwordHash,
		CreatedAt:    now,
		UpdatedAt:    now,
	}, nil
}

type Public struct {
	ID        uuid.UUID `json:"id"`
	Name      string    `json:"name"`
	IsPrivate bool      `json:"isPrivate"`
	OwnerID   uuid.UUID `json:"ownerId"`
	Members   int       `json:"members"`
	Online    int       `json:"online"`
}

func (c *Channel) Public(memberCount int) Public {
	return Public{
		ID:        c.ID,
		Name:      c.Name,
		IsPrivate: c.IsPrivate,
		OwnerID:   c.OwnerID,
		Members:   memberCount,
	}
}
