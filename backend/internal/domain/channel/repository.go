package channel

import (
	"context"
	"errors"

	"github.com/google/uuid"
)

var ErrNotFound = errors.New("channel not found")

type Repository interface {
	Create(ctx context.Context, c *Channel) error
	FindByID(ctx context.Context, id uuid.UUID) (*Channel, error)
	List(ctx context.Context) ([]*Channel, error)
	CountMembers(ctx context.Context, channelID uuid.UUID) (int, error)
	AddMember(ctx context.Context, channelID, userID uuid.UUID) error
	IsMember(ctx context.Context, channelID, userID uuid.UUID) (bool, error)
}
