package postgres

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/lucas/radio-px-backend/internal/domain/admin"
	domainchannel "github.com/lucas/radio-px-backend/internal/domain/channel"
)

type AdminRepository struct{ pool *pgxpool.Pool }

func NewAdminRepository(pool *pgxpool.Pool) *AdminRepository {
	return &AdminRepository{pool: pool}
}

func (r *AdminRepository) Summary(ctx context.Context) (admin.Summary, error) {
	var result admin.Summary
	err := r.pool.QueryRow(ctx, `SELECT (SELECT count(*) FROM users),
		(SELECT count(*) FROM channels), (SELECT count(*) FROM channel_members)`).Scan(
		&result.Users, &result.Channels, &result.Memberships)
	return result, err
}

func (r *AdminRepository) Users(ctx context.Context, search string, page int) (admin.Page[admin.User], error) {
	result := admin.Page[admin.User]{Items: []admin.User{}, Page: page, PageSize: 20}
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return result, err
	}
	defer tx.Rollback(ctx)
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM users WHERE strpos(lower(username), lower($1)) > 0`, search).Scan(&result.Total); err != nil {
		return result, err
	}
	rows, err := tx.Query(ctx, `SELECT id, username, created_at FROM users
		WHERE strpos(lower(username), lower($1)) > 0 ORDER BY created_at DESC, id
		LIMIT 20 OFFSET $2`, search, (page-1)*20)
	if err != nil {
		return result, err
	}
	for rows.Next() {
		var item admin.User
		if err := rows.Scan(&item.ID, &item.Username, &item.CreatedAt); err != nil {
			rows.Close()
			return result, err
		}
		result.Items = append(result.Items, item)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return result, err
	}
	return result, tx.Commit(ctx)
}

func (r *AdminRepository) Channels(ctx context.Context, search string, page int) (admin.Page[admin.Channel], error) {
	result := admin.Page[admin.Channel]{Items: []admin.Channel{}, Page: page, PageSize: 20}
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return result, err
	}
	defer tx.Rollback(ctx)
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM channels WHERE strpos(lower(name), lower($1)) > 0`, search).Scan(&result.Total); err != nil {
		return result, err
	}
	rows, err := tx.Query(ctx, `SELECT c.id, c.name, u.username, c.is_private, c.created_at,
		(SELECT count(*) FROM channel_members m WHERE m.channel_id = c.id)
		FROM channels c JOIN users u ON u.id = c.owner_id
		WHERE strpos(lower(c.name), lower($1)) > 0 ORDER BY c.created_at DESC, c.id
		LIMIT 20 OFFSET $2`, search, (page-1)*20)
	if err != nil {
		return result, err
	}
	for rows.Next() {
		var item admin.Channel
		if err := rows.Scan(&item.ID, &item.Name, &item.Owner, &item.IsPrivate, &item.CreatedAt, &item.Members); err != nil {
			rows.Close()
			return result, err
		}
		result.Items = append(result.Items, item)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return result, err
	}
	return result, tx.Commit(ctx)
}

func (r *AdminRepository) Drivers(ctx context.Context, excluded []uuid.UUID) ([]admin.DriverRecord, error) {
	if excluded == nil {
		excluded = []uuid.UUID{}
	}
	rows, err := r.pool.Query(ctx, `SELECT u.id, u.username, u.first_name, u.last_name, u.vehicle_plate,
		l.latitude, l.longitude, l.created_at
		FROM users u
		LEFT JOIN LATERAL (
			SELECT latitude, longitude, created_at FROM locations
			WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
		) l ON true
		WHERE u.role <> 'admin' AND NOT (u.id = ANY($1))
		ORDER BY u.username`, excluded)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []admin.DriverRecord{}
	for rows.Next() {
		var d admin.DriverRecord
		if err := rows.Scan(&d.ID, &d.Username, &d.FirstName, &d.LastName, &d.VehiclePlate,
			&d.Lat, &d.Lng, &d.ReportedAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (r *AdminRepository) DeleteChannel(ctx context.Context, id uuid.UUID) error {
	result, err := r.pool.Exec(ctx, `DELETE FROM channels WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return domainchannel.ErrNotFound
	}
	return nil
}
