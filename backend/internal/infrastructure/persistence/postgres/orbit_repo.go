package postgres

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
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

func (r *OrbitRepository) List(ctx context.Context, activeOnly bool) ([]orbit.Orbit, error) {
	query := `SELECT ` + orbitColumns + ` FROM orbits`
	if activeOnly {
		query += ` WHERE active`
	}
	query += ` ORDER BY lower(name), created_at`

	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []orbit.Orbit{}
	for rows.Next() {
		var o orbit.Orbit
		if err := rows.Scan(&o.ID, &o.Name, &o.Identifier, &o.Active, &o.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

func (r *OrbitRepository) Get(ctx context.Context, id uuid.UUID) (*orbit.Orbit, error) {
	return r.one(ctx, `SELECT `+orbitColumns+` FROM orbits WHERE id = $1`, id)
}

func (r *OrbitRepository) FindByIdentifier(ctx context.Context, identifier string) (*orbit.Orbit, error) {
	return r.one(ctx, `SELECT `+orbitColumns+` FROM orbits WHERE identifier = $1`, identifier)
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

func (r *OrbitRepository) Create(ctx context.Context, o *orbit.Orbit) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO orbits (`+orbitColumns+`) VALUES ($1, $2, $3, $4, $5)`,
		o.ID, o.Name, o.Identifier, o.Active, o.CreatedAt)
	return mapOrbitErr(err)
}

func (r *OrbitRepository) Update(ctx context.Context, o *orbit.Orbit) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE orbits SET name = $2, identifier = $3, active = $4 WHERE id = $1`,
		o.ID, o.Name, o.Identifier, o.Active)
	if err != nil {
		return mapOrbitErr(err)
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

func mapOrbitErr(err error) error {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return orbit.ErrDuplicate
	}
	return err
}
