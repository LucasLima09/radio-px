package channel

import (
	"context"
	"math"
	"sort"

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
	Latitude  *float64
	Longitude *float64
	OwnerID   uuid.UUID
	Name      string
	IsPrivate bool
}

func (s *Service) Create(ctx context.Context, in CreateInput) (domainchannel.Public, error) {
	if err := domainchannel.ValidateLocation(in.Latitude, in.Longitude); err != nil {
		return domainchannel.Public{}, err
	}
	ch, err := domainchannel.New(in.OwnerID, in.Name, in.IsPrivate)
	if err != nil {
		return domainchannel.Public{}, err
	}
	ch.Latitude, ch.Longitude = in.Latitude, in.Longitude
	if err := s.channels.Create(ctx, ch); err != nil {
		return domainchannel.Public{}, err
	}
	if err := s.channels.AddMember(ctx, ch.ID, in.OwnerID); err != nil {
		return domainchannel.Public{}, err
	}
	return ch.Public(1), nil
}

type ListInput struct {
	Latitude  *float64
	Longitude *float64
	RadiusKm  float64
}

func (s *Service) List(ctx context.Context, in ListInput) ([]domainchannel.Public, error) {
	if err := domainchannel.ValidateLocation(in.Latitude, in.Longitude); err != nil {
		return nil, err
	}
	if in.Latitude != nil && (math.IsNaN(in.RadiusKm) || math.IsInf(in.RadiusKm, 0) || in.RadiusKm <= 0 || in.RadiusKm > 500) {
		return nil, domainchannel.ErrInvalidRadius
	}
	channels, err := s.channels.List(ctx)
	if err != nil {
		return nil, err
	}
	result := make([]domainchannel.Public, 0, len(channels))
	for _, ch := range channels {
		var distance *float64
		if in.Latitude != nil {
			if ch.IsPrivate || ch.Latitude == nil || ch.Longitude == nil {
				continue
			}
			d := domainchannel.DistanceKm(*in.Latitude, *in.Longitude, *ch.Latitude, *ch.Longitude)
			if d > in.RadiusKm {
				continue
			}
			distance = &d
		}
		count, err := s.channels.CountMembers(ctx, ch.ID)
		if err != nil {
			return nil, err
		}
		item := ch.Public(count)
		item.DistanceKm = distance
		result = append(result, item)
	}
	if in.Latitude != nil {
		sort.SliceStable(result, func(i, j int) bool { return *result[i].DistanceKm < *result[j].DistanceKm })
	}
	return result, nil
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
