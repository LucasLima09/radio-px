package ws

import (
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/user"
)

func TestChannelOnlineCountsDistinctUsers(t *testing.T) {
	hub := NewHub(slog.New(slog.NewTextHandler(io.Discard, nil)), time.Minute, 10, 1024, 4096)
	defer hub.Stop()
	handler := &Handler{hub: hub}

	if got := handler.ChannelOnline(); len(got) != 0 {
		t.Fatalf("no active rooms expected, got %v", got)
	}

	channelID := uuid.New()
	room := hub.getOrCreateRoom(channelID, "Central")
	alice := &user.User{ID: uuid.New(), Username: "alice"}
	bob := &user.User{ID: uuid.New(), Username: "bob"}

	alicePhone := newClient(room, alice, nil, nil)
	aliceTablet := newClient(room, alice, nil, nil)
	bobPhone := newClient(room, bob, nil, nil)
	room.add(alicePhone)
	room.add(aliceTablet)
	room.add(bobPhone)

	got := handler.ChannelOnline()
	if got[channelID] != 2 {
		t.Fatalf("two distinct users expected, got %d (%v)", got[channelID], got)
	}

	// Same account on a second device must not inflate the count.
	room.remove(aliceTablet)
	if got := handler.ChannelOnline(); got[channelID] != 2 {
		t.Fatalf("distinct-users count changed unexpectedly: %v", got)
	}

	room.remove(alicePhone)
	if got := handler.ChannelOnline(); got[channelID] != 1 {
		t.Fatalf("one remaining user expected, got %v", got)
	}
}
