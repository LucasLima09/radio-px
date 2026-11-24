package postgres

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/lucas/radio-px-backend/internal/domain/orbit"
)

type OrbitRepository struct {
	pool *pgxpool.Pool
}

func NewOrbitRepository(pool *pgxpool.Pool) *OrbitRepository {
	return &OrbitRepository{pool: pool}
}

const orbitColumns = `id, name, identifier, active, created_at`

func (r *OrbitRepository) List(ctx context.Context) ([]orbit.Orbit, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT o.id, o.name, o.identifier, o.active, o.created_at, l.latitude, l.longitude, l.created_at
		 FROM orbits o
		 LEFT JOIN LATERAL (
		     SELECT latitude, longitude, created_at FROM locations
		     WHERE orbit_id = o.id ORDER BY created_at DESC LIMIT 1
		 ) l ON true
		 ORDER BY lower(o.name), o.created_at`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []orbit.Orbit{}
	for rows.Next() {
		var (
			o        orbit.Orbit
			lat, lng *float64
			at       *time.Time
		)
		if err := rows.Scan(&o.ID, &o.Name, &o.Identifier, &o.Active, &o.CreatedAt, &lat, &lng, &at); err != nil {
			return nil, err
		}
		if lat != nil && lng != nil && at != nil {
			o.Last = &orbit.LastSignal{Latitude: *lat, Longitude: *lng, At: *at}
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

func (r *OrbitRepository) Get(ctx context.Context, id uuid.UUID) (*orbit.Orbit, error) {
	return r.one(ctx, `SELECT `+orbitColumns+` FROM orbits WHERE id = $1`, id)
}

func (r *OrbitRepository) Ensure(ctx context.Context, identifier string) (*orbit.Orbit, error) {
	const find = `SELECT ` + orbitColumns + ` FROM orbits WHERE identifier = $1`
	o, err := r.one(ctx, find, identifier)
	if !errors.Is(err, orbit.ErrNotFound) {
		return o, err
	}
	o = orbit.Discovered(identifier)
	// Dois motoristas podem entregar o primeiro sinal ao mesmo tempo: quem
	// perder a corrida usa a linha criada pelo outro.
	if _, err := r.pool.Exec(ctx,
		`INSERT INTO orbits (`+orbitColumns+`) VALUES ($1, $2, $3, $4, $5)
		 ON CONFLICT (identifier) DO NOTHING`,
		o.ID, o.Name, o.Identifier, o.Active, o.CreatedAt); err != nil {
		return nil, err
	}
	return r.one(ctx, find, identifier)
}

func (r *OrbitRepository) one(ctx context.Context, query string, arg any) (*orbit.Orbit, error) {
	var o orbit.Orbit
	err := r.pool.QueryRow(ctx, query, arg).Scan(&o.ID, &o.Name, &o.Identifier, &o.Active, &o.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, orbit.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &o, nil
}

func (r *OrbitRepository) Update(ctx context.Context, o *orbit.Orbit) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE orbits SET name = $2, active = $3 WHERE id = $1`, o.ID, o.Name, o.Active)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return orbit.ErrNotFound
	}
	return nil
}

func (r *OrbitRepository) Delete(ctx context.Context, id uuid.UUID) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM orbits WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return orbit.ErrNotFound
	}
	return nil
}
