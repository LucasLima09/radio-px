package location

import (
	"context"

	"github.com/google/uuid"
)

type Repository interface {
	Save(ctx context.Context, loc *Location) error
	LatestByUser(ctx context.Context) ([]Report, error)
	// History devolve os últimos reports de localização, mais recentes primeiro,
	// opcionalmente filtrados por usuário. limit restringe o número de linhas.
	History(ctx context.Context, userID *uuid.UUID, limit int) ([]Report, error)
}
