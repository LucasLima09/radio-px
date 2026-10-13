package admin

import (
	"context"
	"time"

	"github.com/google/uuid"
)

type Summary struct {
	Users       int `json:"users"`
	Channels    int `json:"channels"`
	Memberships int `json:"memberships"`
}

type User struct {
	ID        uuid.UUID `json:"id"`
	Username  string    `json:"username"`
	CreatedAt time.Time `json:"createdAt"`
}

type Channel struct {
	ID        uuid.UUID `json:"id"`
	Name      string    `json:"name"`
	Owner     string    `json:"owner"`
	Members   int       `json:"members"`
	IsPrivate bool      `json:"isPrivate"`
	CreatedAt time.Time `json:"createdAt"`
}

type Page[T any] struct {
	Items    []T `json:"items"`
	Total    int `json:"total"`
	Page     int `json:"page"`
	PageSize int `json:"pageSize"`
}

type Repository interface {
	Summary(context.Context) (Summary, error)
	Users(context.Context, string, int) (Page[User], error)
	Channels(context.Context, string, int) (Page[Channel], error)
	DeleteChannel(context.Context, uuid.UUID) error
}
