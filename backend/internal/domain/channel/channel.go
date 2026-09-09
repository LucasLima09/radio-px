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
)

type Channel struct {
	ID        uuid.UUID
	OwnerID   uuid.UUID
	Name      string
	IsPrivate bool
	CreatedAt time.Time
	UpdatedAt time.Time
}

func New(ownerID uuid.UUID, name string, isPrivate bool) (*Channel, error) {
	name = strings.TrimSpace(name)
	if len(name) == 0 {
		return nil, ErrInvalidChannelName
	}

	now := time.Now().UTC()
	return &Channel{
		ID:        uuid.New(),
		OwnerID:   ownerID,
		Name:      name,
		IsPrivate: isPrivate,
		CreatedAt: now,
		UpdatedAt: now,
	}, nil
}

type Public struct {
	ID        uuid.UUID `json:"id"`
	Name      string    `json:"name"`
	IsPrivate bool      `json:"isPrivate"`
	OwnerID   uuid.UUID `json:"ownerId"`
	Members   int       `json:"members"`
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
