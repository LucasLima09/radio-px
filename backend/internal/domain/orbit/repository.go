package orbit

import (
	"context"
	"errors"

	"github.com/google/uuid"
)

var (
	ErrNotFound  = errors.New("orbit not found")
	ErrDuplicate = errors.New("orbit identifier already registered")
)

type Repository interface {
	// List devolve os Orbits por nome; com activeOnly, só os ativos.
	List(ctx context.Context, activeOnly bool) ([]Orbit, error)
	Get(ctx context.Context, id uuid.UUID) (*Orbit, error)
	// FindByIdentifier procura pelo nome anunciado no Bluetooth.
	FindByIdentifier(ctx context.Context, identifier string) (*Orbit, error)
	Create(ctx context.Context, o *Orbit) error
	Update(ctx context.Context, o *Orbit) error
	Delete(ctx context.Context, id uuid.UUID) error
}
