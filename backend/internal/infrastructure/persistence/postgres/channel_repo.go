package postgres

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	domainchannel "github.com/lucas/radio-px-backend/internal/domain/channel"
)

type ChannelRepository struct {
	pool *pgxpool.Pool
}

func NewChannelRepository(pool *pgxpool.Pool) *ChannelRepository {
	return &ChannelRepository{pool: pool}
}

const channelColumns = "id, owner_id, name, is_private, created_at, updated_at, latitude, longitude"

func (r *ChannelRepository) Create(ctx context.Context, c *domainchannel.Channel) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO channels (id, owner_id, name, is_private, created_at, updated_at, latitude, longitude)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		c.ID, c.OwnerID, c.Name, c.IsPrivate, c.CreatedAt, c.UpdatedAt, c.Latitude, c.Longitude,
	)
	return err
}

func (r *ChannelRepository) FindByID(ctx context.Context, id uuid.UUID) (*domainchannel.Channel, error) {
	row := r.pool.QueryRow(ctx, `SELECT `+channelColumns+` FROM channels WHERE id = $1`, id)
	var c domainchannel.Channel
	if err := row.Scan(&c.ID, &c.OwnerID, &c.Name, &c.IsPrivate, &c.CreatedAt, &c.UpdatedAt, &c.Latitude, &c.Longitude); err != nil {
		return nil, translateError(err)
	}
	return &c, nil
}

func (r *ChannelRepository) List(ctx context.Context) ([]*domainchannel.Channel, error) {
	rows, err := r.pool.Query(ctx, `SELECT `+channelColumns+` FROM channels ORDER BY created_at ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*domainchannel.Channel
	for rows.Next() {
		var c domainchannel.Channel
		if err := rows.Scan(&c.ID, &c.OwnerID, &c.Name, &c.IsPrivate, &c.CreatedAt, &c.UpdatedAt, &c.Latitude, &c.Longitude); err != nil {
			return nil, err
		}
		out = append(out, &c)
	}
	return out, rows.Err()
}

func (r *ChannelRepository) CountMembers(ctx context.Context, channelID uuid.UUID) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM channel_members WHERE channel_id = $1`, channelID,
	).Scan(&count)
	return count, err
}

func (r *ChannelRepository) AddMember(ctx context.Context, channelID, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO channel_members (channel_id, user_id) VALUES ($1, $2)
		 ON CONFLICT (channel_id, user_id) DO NOTHING`,
		channelID, userID,
	)
	return err
}

func (r *ChannelRepository) IsMember(ctx context.Context, channelID, userID uuid.UUID) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM channel_members WHERE channel_id = $1 AND user_id = $2)`,
		channelID, userID,
	).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}
