package postgres

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/lucas/radio-px-backend/internal/domain/location"
)

type LocationRepository struct {
	pool *pgxpool.Pool
}

func NewLocationRepository(pool *pgxpool.Pool) *LocationRepository {
	return &LocationRepository{pool: pool}
}

func (r *LocationRepository) Save(ctx context.Context, loc *location.Location) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO locations (id, user_id, channel_id, latitude, longitude, created_at)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		loc.ID, loc.UserID, loc.ChannelID, loc.Latitude, loc.Longitude, loc.CreatedAt,
	)
	return err
}
