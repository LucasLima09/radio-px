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

func newSizedClip(size int) *Clip {
	c := newTestClip(size)
	c.Data = make([]byte, size)
	return c
}

func seqs(clips []*Clip) []int64 {
	out := make([]int64, len(clips))
	for i, c := range clips {
		out[i] = c.Seq
	}
	return out
}

func equalSeqs(got []*Clip, want ...int64) bool {
	if len(got) != len(want) {
		return false
	}
	for i, c := range got {
		if c.Seq != want[i] {
			return false
		}
	}
	return true
}

func TestClipQueueFIFOOrdering(t *testing.T) {
	q := newClipQueue(time.Hour, 100, 5<<20)
	for i := 0; i < 5; i++ {
		q.add(newTestClip(i))
	}
	snap := q.snapshotSince(0)
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
	if len(q.snapshotSince(0)) != 0 {
		t.Fatal("expected empty snapshot after expiry")
	}
}

func TestClipQueueMaxClips(t *testing.T) {
	q := newClipQueue(time.Hour, 3, 5<<20)
	for i := 0; i < 10; i++ {
		q.add(newTestClip(i))
	}
	snap := q.snapshotSince(0)
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
	a.Seq = 1
	a.Received = time.Now().Add(-2 * time.Hour)
	b := newTestClip(2)
	b.Seq = 2
	b.Received = time.Now()
	q.mu.Lock()
	q.clips = []*Clip{a, b}
	q.bytes = int64(len(a.Data) + len(b.Data))
	q.seq = 2
	q.mu.Unlock()

	snap := q.snapshotSince(0)
	if len(snap) != 1 || snap[0] != b {
		t.Fatalf("expected only the fresh clip to survive, got %d clips", len(snap))
	}
}

func TestClipQueueByteBudget(t *testing.T) {
	q := newClipQueue(time.Hour, 100, 10)
	for i := 0; i < 3; i++ {
		q.add(newSizedClip(4))
	}
	if got := seqs(q.snapshotSince(0)); len(got) != 2 || got[0] != 2 || got[1] != 3 {
		t.Fatalf("expected seqs 2,3 after the byte budget dropped the oldest, got %v", got)
	}
	q.mu.Lock()
	bytes := q.bytes
	q.mu.Unlock()
	if bytes != 8 {
		t.Fatalf("expected bytes counter to track the queue (8), got %d", bytes)
	}
}

func TestClipQueueByteBudgetDropsOversizedClip(t *testing.T) {
	q := newClipQueue(time.Hour, 100, 4)
	q.add(newSizedClip(2))
	q.add(newSizedClip(8))
	if got := q.snapshotSince(0); len(got) != 0 {
		t.Fatalf("expected a clip larger than the whole budget to be dropped, got %d", len(got))
	}
	q.mu.Lock()
	bytes := q.bytes
	q.mu.Unlock()
	if bytes != 0 {
		t.Fatalf("expected bytes counter to return to 0, got %d", bytes)
	}
}

func TestDropClearsBackingArraySlot(t *testing.T) {
	q := newClipQueue(time.Hour, 1, 1<<20)
	a := newSizedClip(4)
	b := newSizedClip(4)
	q.mu.Lock()
	q.clips = []*Clip{a, b}
	q.bytes = 8
	q.seq = 2
	backing := q.clips
	q.trimLocked()
	if len(q.clips) != 1 || q.clips[0] != b {
		q.mu.Unlock()
		t.Fatalf("expected only the second clip to survive, got %d clips", len(q.clips))
	}
	if backing[0] != nil {
		q.mu.Unlock()
		t.Fatal("dropped clip is still referenced by the backing array, so its data cannot be collected")
	}
	if q.bytes != 4 {
		q.mu.Unlock()
		t.Fatalf("expected bytes 4 after trim, got %d", q.bytes)
	}
	q.mu.Unlock()
}

func TestSnapshotSinceSkipsListenedClips(t *testing.T) {
	q := newClipQueue(time.Hour, 100, 5<<20)
	for i := 0; i < 5; i++ {
		q.add(newTestClip(i))
	}
	if got := q.snapshotSince(2); !equalSeqs(got, 3, 4, 5) {
		t.Fatalf("expected seqs 3,4,5 after listening to 1,2, got %v", seqs(got))
	}
	if got := q.snapshotSince(4); !equalSeqs(got, 5) {
		t.Fatalf("expected seqs 5, got %v", seqs(got))
	}
	if got := q.snapshotSince(5); len(got) != 0 {
		t.Fatalf("expected nothing after listening to the whole queue, got %v", seqs(got))
	}
}

func TestSnapshotSinceZeroCursorReturnsEverything(t *testing.T) {
	q := newClipQueue(time.Hour, 100, 5<<20)
	for i := 0; i < 3; i++ {
		q.add(newTestClip(i))
	}
	if got := q.snapshotSince(0); !equalSeqs(got, 1, 2, 3) {
		t.Fatalf("expected the full history on a first visit, got %v", seqs(got))
	}
}

// The hub drops empty queues and recreates them with Seq restarting at 1. A
// cursor carried over from the previous queue would otherwise hide every clip
// on the new one.
func TestSnapshotSinceIgnoresCursorFromRecreatedQueue(t *testing.T) {
	q := newClipQueue(time.Hour, 100, 5<<20)
	for i := 0; i < 3; i++ {
		q.add(newTestClip(i))
	}
	if got := q.snapshotSince(57); !equalSeqs(got, 1, 2, 3) {
		t.Fatalf("expected a stale cursor to be ignored, got %v", seqs(got))
	}
}

// The oldest clips expire and are dropped, so the queue no longer starts at 1.
func TestSnapshotSinceClampsCursorBelowFirstSeq(t *testing.T) {
	q := newClipQueue(time.Hour, 3, 5<<20)
	for i := 0; i < 5; i++ {
		q.add(newTestClip(i))
	}
	if got := q.snapshotSince(1); !equalSeqs(got, 3, 4, 5) {
		t.Fatalf("expected a cursor below the oldest held clip to be clamped, got %v", seqs(got))
	}
}

func TestSnapshotSinceNegativeCursorReturnsEverything(t *testing.T) {
	q := newClipQueue(time.Hour, 100, 5<<20)
	q.add(newTestClip(1))
	q.add(newTestClip(2))
	if got := q.snapshotSince(-1); !equalSeqs(got, 1, 2) {
		t.Fatalf("expected a negative cursor to be treated as a first visit, got %v", seqs(got))
	}
}

func TestSnapshotSinceEmptyQueue(t *testing.T) {
	q := newClipQueue(time.Hour, 100, 5<<20)
	if got := q.snapshotSince(42); len(got) != 0 {
		t.Fatalf("expected nothing from an empty queue, got %d clips", len(got))
	}
}
