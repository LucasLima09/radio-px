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
	owner, stranger := uuid.New(), uuid.New()

	public, err := svc.Create(ctx, CreateInput{OwnerID: owner, Name: "Geral"})
	if err != nil {
		t.Fatalf("create public: %v", err)
	}
	private, err := svc.Create(ctx, CreateInput{OwnerID: owner, Name: "Diretoria", IsPrivate: true, Password: "segredo"})
	if err != nil {
		t.Fatalf("create private: %v", err)
	}

	if got := len(svc.List(ctx)); got != 2 {
		t.Fatalf("private channels must be listed so people can join them, saw %d", got)
	}

	if _, err := svc.Join(ctx, public.ID, stranger, ""); err != nil {
		t.Fatalf("anyone joins a public channel: %v", err)
	}
	if _, err := svc.Join(ctx, private.ID, owner, ""); err != nil {
		t.Fatalf("owner joins without password: %v", err)
	}
	if _, err := svc.Join(ctx, private.ID, stranger, ""); !errors.Is(err, domainchannel.ErrPasswordRequired) {
		t.Fatalf("stranger without password: want ErrPasswordRequired, got %v", err)
	}
	if _, err := svc.Join(ctx, private.ID, stranger, "errada"); !errors.Is(err, domainchannel.ErrWrongPassword) {
		t.Fatalf("stranger with wrong password: want ErrWrongPassword, got %v", err)
	}
	if _, err := svc.Join(ctx, private.ID, stranger, "segredo"); err != nil {
		t.Fatalf("stranger with right password: %v", err)
	}
	if _, err := svc.Join(ctx, private.ID, stranger, ""); err != nil {
		t.Fatalf("a member rejoins without password: %v", err)
	}
}

func TestCreatePrivateChannelPassword(t *testing.T) {
	ctx := context.Background()
	svc := NewService(newMemoryChannelRepo(), nil)
	owner := uuid.New()

	if _, err := svc.Create(ctx, CreateInput{OwnerID: owner, Name: "Sem senha", IsPrivate: true}); !errors.Is(err, domainchannel.ErrWeakPassword) {
		t.Fatalf("private channel without password: want ErrWeakPassword, got %v", err)
	}
	if _, err := svc.Create(ctx, CreateInput{OwnerID: owner, Name: "Curta", IsPrivate: true, Password: "123"}); !errors.Is(err, domainchannel.ErrWeakPassword) {
		t.Fatalf("short password: want ErrWeakPassword, got %v", err)
	}

	public, err := svc.Create(ctx, CreateInput{OwnerID: owner, Name: "Aberto", Password: "ignorada"})
	if err != nil {
		t.Fatalf("create public: %v", err)
	}
	stored, _ := svc.channels.FindByID(ctx, public.ID)
	if stored.PasswordHash != "" {
		t.Fatal("public channels must not store a password")
	}
}
