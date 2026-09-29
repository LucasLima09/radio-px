package location

import (
	"errors"
	"time"

	"github.com/google/uuid"
)

var (
	ErrInvalidCoord = errors.New("invalid coordinates")
)

type Location struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	ChannelID uuid.UUID
	Latitude  float64
	Longitude float64
	CreatedAt time.Time
}

func New(userID, channelID uuid.UUID, latitude, longitude float64) (*Location, error) {
	if latitude < -90 || latitude > 90 {
		return nil, ErrInvalidCoord
	}
	if longitude < -180 || longitude > 180 {
		return nil, ErrInvalidCoord
	}

	return &Location{
		ID:        uuid.New(),
		UserID:    userID,
		ChannelID: channelID,
		Latitude:  latitude,
		Longitude: longitude,
		CreatedAt: time.Now().UTC(),
	}, nil
}
