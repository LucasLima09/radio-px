package channel

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	domainchannel "github.com/lucas/radio-px-backend/internal/domain/channel"
)

type memoryChannelRepo struct {
	channels map[uuid.UUID]*domainchannel.Channel
	members  map[uuid.UUID]map[uuid.UUID]bool
}

func newMemoryChannelRepo() *memoryChannelRepo {
	return &memoryChannelRepo{
		channels: map[uuid.UUID]*domainchannel.Channel{},
		members:  map[uuid.UUID]map[uuid.UUID]bool{},
	}
}

func (r *memoryChannelRepo) Create(_ context.Context, c *domainchannel.Channel) error {
	r.channels[c.ID] = c
	return nil
}

func (r *memoryChannelRepo) FindByID(_ context.Context, id uuid.UUID) (*domainchannel.Channel, error) {
	c, ok := r.channels[id]
	if !ok {
		return nil, domainchannel.ErrNotFound
	}
	return c, nil
}

func (r *memoryChannelRepo) List(_ context.Context) ([]*domainchannel.Channel, error) {
	out := make([]*domainchannel.Channel, 0, len(r.channels))
	for _, c := range r.channels {
		out = append(out, c)
	}
	return out, nil
}

func (r *memoryChannelRepo) CountMembers(_ context.Context, id uuid.UUID) (int, error) {
	return len(r.members[id]), nil
}

func (r *memoryChannelRepo) AddMember(_ context.Context, channelID, userID uuid.UUID) error {
	if r.members[channelID] == nil {
		r.members[channelID] = map[uuid.UUID]bool{}
	}
	r.members[channelID][userID] = true
	return nil
}

func (r *memoryChannelRepo) IsMember(_ context.Context, channelID, userID uuid.UUID) (bool, error) {
	return r.members[channelID][userID], nil
}

func TestPrivateChannelAccess(t *testing.T) {
	ctx := context.Background()
	svc := NewService(newMemoryChannelRepo(), nil)
	owner, member, stranger := uuid.New(), uuid.New(), uuid.New()

	public, err := svc.Create(ctx, CreateInput{OwnerID: owner, Name: "Geral"})
	if err != nil {
		t.Fatalf("create public: %v", err)
	}
	private, err := svc.Create(ctx, CreateInput{OwnerID: owner, Name: "Diretoria", IsPrivate: true})
	if err != nil {
		t.Fatalf("create private: %v", err)
	}
	if err := svc.channels.AddMember(ctx, private.ID, member); err != nil {
		t.Fatalf("add member: %v", err)
	}

	if got := len(svc.List(ctx, stranger)); got != 1 {
		t.Fatalf("stranger should only see the public channel, saw %d", got)
	}
	if got := len(svc.List(ctx, member)); got != 2 {
		t.Fatalf("member should see both channels, saw %d", got)
	}

	if _, err := svc.GetVisible(ctx, private.ID, stranger); !errors.Is(err, domainchannel.ErrNotFound) {
		t.Fatalf("stranger must not see the private channel, got %v", err)
	}
	if _, err := svc.Join(ctx, private.ID, stranger); !errors.Is(err, domainchannel.ErrPrivateChannel) {
		t.Fatalf("stranger must not join the private channel, got %v", err)
	}
	if _, err := svc.Join(ctx, private.ID, member); err != nil {
		t.Fatalf("existing member must rejoin: %v", err)
	}
	if _, err := svc.Join(ctx, public.ID, stranger); err != nil {
		t.Fatalf("anyone joins a public channel: %v", err)
	}
}
