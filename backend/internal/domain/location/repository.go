package location

import "context"

type Repository interface {
	Save(ctx context.Context, loc *Location) error
}
