package ws

import (
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/user"
)

func TestSendClipTakesOneQueueSlot(t *testing.T) {
	hub := NewHub(slog.New(slog.NewTextHandler(io.Discard, nil)), time.Minute, 10, 1<<20, 4<<20)
	defer hub.Stop()
	room := hub.getOrCreateRoom(uuid.New(), "Central")
	c := newClient(room, &user.User{ID: uuid.New(), Username: "alice"}, nil, nil)

	// A clip far larger than one chunk must still be a single queue entry, so
	// it can never be partially dropped.
	c.sendClip(&Clip{ID: uuid.New(), Data: make([]byte, 10*clipPayloadChunk)})
	if got := len(c.sendCh); got != 1 {
		t.Fatalf("expected 1 queued entry, got %d", got)
	}
}

func TestSendQueueFitsFullSnapshot(t *testing.T) {
	hub := NewHub(slog.New(slog.NewTextHandler(io.Discard, nil)), time.Minute, 1000, 1<<20, 4<<20)
	defer hub.Stop()
	room := hub.getOrCreateRoom(uuid.New(), "Central")
	c := newClient(room, &user.User{ID: uuid.New(), Username: "alice"}, nil, nil)

	if cap(c.sendCh) <= hub.maxClips {
		t.Fatalf("queue (%d) must hold a full clip snapshot (%d)", cap(c.sendCh), hub.maxClips)
	}
}

func TestOverflowMarksClientSlow(t *testing.T) {
	hub := NewHub(slog.New(slog.NewTextHandler(io.Discard, nil)), time.Minute, 10, 1<<20, 4<<20)
	defer hub.Stop()
	room := hub.getOrCreateRoom(uuid.New(), "Central")
	c := newClient(room, &user.User{ID: uuid.New(), Username: "alice"}, nil, nil)

	for range cap(c.sendCh) + 1 {
		c.pushFrame(outboundFrame{Kind: frameText, Data: []byte("{}")})
	}
	ran := false
	c.slowOnce.Do(func() { ran = true })
	if ran {
		t.Fatal("overflow must trigger dropSlow")
	}
}
