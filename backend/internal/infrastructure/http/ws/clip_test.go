package ws

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func newTestClip(i int) *Clip {
	return &Clip{
		ID:       uuid.New(),
		UserID:   uuid.New(),
		Username: "user",
		MIME:     "audio/mp4",
		Duration: 3 * time.Second,
		Data:     []byte{byte(i)},
	}
}

func TestClipQueueFIFOOrdering(t *testing.T) {
	q := newClipQueue(time.Hour, 100, 5<<20)
	for i := 0; i < 5; i++ {
		q.add(newTestClip(i))
	}
	snap := q.snapshot()
	if len(snap) != 5 {
		t.Fatalf("expected 5 clips, got %d", len(snap))
	}
	for i, c := range snap {
		if c.Seq != int64(i+1) {
			t.Errorf("clip %d: expected seq %d, got %d", i, i+1, c.Seq)
		}
	}
}

func TestClipQueueExpiry(t *testing.T) {
	ttl := 50 * time.Millisecond
	q := newClipQueue(ttl, 100, 5<<20)
	q.add(newTestClip(1))
	if n := q.sweep(time.Now()); n != 1 {
		t.Fatalf("expected 1 clip before expiry, got %d", n)
	}
	time.Sleep(ttl + 20*time.Millisecond)
	if n := q.sweep(time.Now()); n != 0 {
		t.Fatalf("expected 0 clips after expiry, got %d", n)
	}
	if len(q.snapshot()) != 0 {
		t.Fatal("expected empty snapshot after expiry")
	}
}

func TestClipQueueMaxClips(t *testing.T) {
	q := newClipQueue(time.Hour, 3, 5<<20)
	for i := 0; i < 10; i++ {
		q.add(newTestClip(i))
	}
	snap := q.snapshot()
	if len(snap) != 3 {
		t.Fatalf("expected queue trimmed to 3, got %d", len(snap))
	}
	if snap[0].Seq != 8 || snap[2].Seq != 10 {
		t.Errorf("expected last three seqs 8,9,10, got %d..%d", snap[0].Seq, snap[2].Seq)
	}
}

func TestClipQueueExpiryOnlyDropsOldest(t *testing.T) {
	ttl := time.Hour
	q := newClipQueue(ttl, 100, 5<<20)
	a := newTestClip(1)
	a.Received = time.Now().Add(-2 * time.Hour)
	b := newTestClip(2)
	b.Received = time.Now()
	q.mu.Lock()
	q.clips = []*Clip{a, b}
	q.seq = 2
	q.mu.Unlock()

	snap := q.snapshot()
	if len(snap) != 1 || snap[0] != b {
		t.Fatalf("expected only the fresh clip to survive, got %d clips", len(snap))
	}
}