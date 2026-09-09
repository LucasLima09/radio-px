package postgres

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/lucas/radio-px-backend/internal/domain/user"
)

type UserRepository struct {
	pool *pgxpool.Pool
}

func NewUserRepository(pool *pgxpool.Pool) *UserRepository {
	return &UserRepository{pool: pool}
}

const userColumns = "id, username, password_hash, created_at, updated_at"

func scanUser(row pgx.Row) (*user.User, error) {
	var u user.User
	if err := row.Scan(&u.ID, &u.Username, &u.PasswordHash, &u.CreatedAt, &u.UpdatedAt); err != nil {
		return nil, err
	}
	return &u, nil
}

func (r *UserRepository) Create(ctx context.Context, u *user.User) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO users (id, username, password_hash, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5)`,
		u.ID, u.Username, u.PasswordHash, u.CreatedAt, u.UpdatedAt,
	)
	if err != nil {
		return translateError(err)
	}
	return nil
}

func (r *UserRepository) FindByUsername(ctx context.Context, username string) (*user.User, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT `+userColumns+` FROM users WHERE username = $1`, username)
	u, err := scanUser(row)
	if err != nil {
		return nil, translateError(err)
	}
	return u, nil
}

func (r *UserRepository) FindByID(ctx context.Context, id uuid.UUID) (*user.User, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT `+userColumns+` FROM users WHERE id = $1`, id)
	u, err := scanUser(row)
	if err != nil {
		return nil, translateError(err)
	}
	return u, nil
}

func translateError(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return user.ErrNotFound
	}
	return err
}
