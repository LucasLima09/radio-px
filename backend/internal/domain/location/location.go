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
	ChannelID *uuid.UUID
	Latitude  float64
	Longitude float64
	CreatedAt time.Time
}

// channelID é nil quando a posição é reportada fora de um canal (beacon
// sempre ativo em segundo plano).
func New(userID uuid.UUID, channelID *uuid.UUID, latitude, longitude float64) (*Location, error) {
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

// Report é a última posição conhecida de um usuário, agregada para o painel do
// admin.
type Report struct {
	UserID    uuid.UUID
	Username  string
	Latitude  float64
	Longitude float64
	ReportedAt time.Time
}
