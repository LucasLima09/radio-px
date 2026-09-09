package channel

import (
	"context"

	"github.com/google/uuid"
	domainchannel "github.com/lucas/radio-px-backend/internal/domain/channel"
	"github.com/lucas/radio-px-backend/internal/domain/user"
)

type Service struct {
	channels domainchannel.Repository
	users    user.Repository
}

func NewService(channels domainchannel.Repository, users user.Repository) *Service {
	return &Service{
		channels: channels,
		users:    users,
	}
}

type CreateInput struct {
	OwnerID   uuid.UUID
	Name      string
	IsPrivate bool
}

func (s *Service) Create(ctx context.Context, in CreateInput) (domainchannel.Public, error) {
	ch, err := domainchannel.New(in.OwnerID, in.Name, in.IsPrivate)
	if err != nil {
		return domainchannel.Public{}, err
	}
	if err := s.channels.Create(ctx, ch); err != nil {
		return domainchannel.Public{}, err
	}
	if err := s.channels.AddMember(ctx, ch.ID, in.OwnerID); err != nil {
		return domainchannel.Public{}, err
	}
	return ch.Public(1), nil
}

func (s *Service) List(ctx context.Context) []domainchannel.Public {
	channels, err := s.channels.List(ctx)
	if err != nil {
		return []domainchannel.Public{}
	}
	result := make([]domainchannel.Public, 0, len(channels))
	for _, ch := range channels {
		count, _ := s.channels.CountMembers(ctx, ch.ID)
		result = append(result, ch.Public(count))
	}
	return result
}

func (s *Service) Get(ctx context.Context, id uuid.UUID) (domainchannel.Public, error) {
	ch, err := s.channels.FindByID(ctx, id)
	if err != nil {
		return domainchannel.Public{}, err
	}
	count, _ := s.channels.CountMembers(ctx, id)
	return ch.Public(count), nil
}

func (s *Service) Join(ctx context.Context, channelID, userID uuid.UUID) (domainchannel.Public, error) {
	ch, err := s.channels.FindByID(ctx, channelID)
	if err != nil {
		return domainchannel.Public{}, err
	}

	isMember, err := s.channels.IsMember(ctx, channelID, userID)
	if err != nil {
		return domainchannel.Public{}, err
	}
	if !isMember {
		if err := s.channels.AddMember(ctx, channelID, userID); err != nil {
			return domainchannel.Public{}, err
		}
	}

	count, _ := s.channels.CountMembers(ctx, channelID)
	return ch.Public(count), nil
}

func (s *Service) IsMember(ctx context.Context, channelID, userID uuid.UUID) (bool, error) {
	return s.channels.IsMember(ctx, channelID, userID)
}
