package orbit

import (
	"context"
	"errors"

	"github.com/google/uuid"
)

var ErrNotFound = errors.New("orbit not found")

type Repository interface {
	// List devolve os Orbits por nome, com a última posição de cada um.
	List(ctx context.Context) ([]Orbit, error)
	Get(ctx context.Context, id uuid.UUID) (*Orbit, error)
	// Ensure devolve o Orbit com esse identificador, criando-o se for a
	// primeira vez que aparece.
	Ensure(ctx context.Context, identifier string) (*Orbit, error)
	Update(ctx context.Context, o *Orbit) error
	Delete(ctx context.Context, id uuid.UUID) error
}
