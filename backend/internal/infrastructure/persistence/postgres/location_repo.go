package postgres

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
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
		`INSERT INTO locations (id, user_id, channel_id, latitude, longitude, orbit_name, orbit_id, rssi, created_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		 ON CONFLICT (id) DO NOTHING`,
		loc.ID, loc.UserID, loc.ChannelID, loc.Latitude, loc.Longitude, loc.OrbitName, loc.OrbitID, loc.RSSI, loc.CreatedAt,
	)
	return err
}

// LatestByUser returns the most recent position of every user who ever reported
// a location, newest first, joined with the username for display.
func (r *LocationRepository) LatestByUser(ctx context.Context) ([]location.Report, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT DISTINCT ON (l.user_id) l.user_id, u.username, l.latitude, l.longitude, l.orbit_name, l.rssi, l.created_at
		 FROM locations l
		 JOIN users u ON u.id = l.user_id
		 ORDER BY l.user_id, l.created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanReports(rows)
}

func (r *LocationRepository) History(ctx context.Context, userID *uuid.UUID, limit int) ([]location.Report, error) {
	query := `SELECT l.user_id, u.username, l.latitude, l.longitude, l.orbit_name, l.rssi, l.created_at
		 FROM locations l
		 JOIN users u ON u.id = l.user_id`
	args := []any{}
	if userID != nil {
		query += ` WHERE l.user_id = $1`
		args = append(args, *userID)
	}
	query += ` ORDER BY l.created_at DESC`
	if limit > 0 {
		query += fmt.Sprintf(" LIMIT %d", limit)
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanReports(rows)
}

func scanReports(rows pgx.Rows) ([]location.Report, error) {
	var out []location.Report
	for rows.Next() {
		var (
			rep  location.Report
			rssi *int16
		)
		if err := rows.Scan(&rep.UserID, &rep.Username, &rep.Latitude, &rep.Longitude,
			&rep.OrbitName, &rssi, &rep.ReportedAt); err != nil {
			return nil, err
		}
		if rssi != nil {
			v := int(*rssi)
			rep.RSSI = &v
		}
		out = append(out, rep)
	}
	return out, rows.Err()
}
