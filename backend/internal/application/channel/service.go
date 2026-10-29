package channel

import (
	"context"

	"github.com/google/uuid"
	domainchannel "github.com/lucas/radio-px-backend/internal/domain/channel"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	"golang.org/x/crypto/bcrypt"
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
	// Password is required for private channels and ignored for public ones.
	Password string
}

func (s *Service) Create(ctx context.Context, in CreateInput) (domainchannel.Public, error) {
	var passwordHash string
	if in.IsPrivate {
		if err := domainchannel.ValidatePassword(in.Password); err != nil {
			return domainchannel.Public{}, err
		}
		hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), bcrypt.DefaultCost)
		if err != nil {
			return domainchannel.Public{}, err
		}
		passwordHash = string(hash)
	}
	ch, err := domainchannel.New(in.OwnerID, in.Name, in.IsPrivate, passwordHash)
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

// List returns every channel. Private ones are listed too, so people can find
// them and join with the password.
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

// Join makes userID a member of the channel. A private channel asks for its
// password only the first time: once a member, the user rejoins freely.
func (s *Service) Join(ctx context.Context, channelID, userID uuid.UUID, password string) (domainchannel.Public, error) {
	ch, err := s.channels.FindByID(ctx, channelID)
	if err != nil {
		return domainchannel.Public{}, err
	}

	isMember, err := s.channels.IsMember(ctx, channelID, userID)
	if err != nil {
		return domainchannel.Public{}, err
	}
	if !isMember {
		if ch.IsPrivate && ch.OwnerID != userID {
			if err := checkPassword(ch, password); err != nil {
				return domainchannel.Public{}, err
			}
		}
		if err := s.channels.AddMember(ctx, channelID, userID); err != nil {
			return domainchannel.Public{}, err
		}
	}

	count, _ := s.channels.CountMembers(ctx, channelID)
	return ch.Public(count), nil
}

func checkPassword(ch *domainchannel.Channel, password string) error {
	if password == "" {
		return domainchannel.ErrPasswordRequired
	}
	// Private channels created before passwords existed have no hash and
	// stay closed to new members.
	if ch.PasswordHash == "" ||
		bcrypt.CompareHashAndPassword([]byte(ch.PasswordHash), []byte(password)) != nil {
		return domainchannel.ErrWrongPassword
	}
	return nil
}

func (s *Service) IsMember(ctx context.Context, channelID, userID uuid.UUID) (bool, error) {
	return s.channels.IsMember(ctx, channelID, userID)
}
