package ws

import (
	"sync"
	"time"

	"github.com/google/uuid"
)

// Clip is a single audio clip kept in the per-channel queue. It lives only in
// memory (never persisted) and is dropped once it expires.
type Clip struct {
	ID       uuid.UUID
	UserID   uuid.UUID
	Username string
	MIME     string
	Duration time.Duration
	Seq      int64
	Received time.Time
	Data     []byte
}

func (c *Clip) info() clipInfo {
	return clipInfo{
		ClipID:     c.ID,
		UserID:     c.UserID,
		Username:   c.Username,
		MIME:       c.MIME,
		DurationMS: c.Duration.Milliseconds(),
		Seq:        c.Seq,
		Size:       int64(len(c.Data)),
	}
}

// ClipQueue is an in-memory FIFO cache of audio clips for a channel. Clips are
// ordered by arrival (Seq) and expire after a TTL. No database is involved.
//
// maxBytes is a budget for the whole queue, not a per-clip limit: the oldest
// clips are dropped until both the count and the total size fit.
type ClipQueue struct {
	mu       sync.Mutex
	ttl      time.Duration
	maxClips int
	maxBytes int64
	seq      int64
	bytes    int64
	clips    []*Clip
}

func newClipQueue(ttl time.Duration, maxClips int, maxBytes int64) *ClipQueue {
	return &ClipQueue{
		ttl:      ttl,
		maxClips: maxClips,
		maxBytes: maxBytes,
	}
}

// add appends a clip to the queue, assigning its sequence number (arrival
// order) and trimming the queue to its limits. The clip is returned even when
// the limits drop it again: connected clients still receive it live, it simply
// is not kept for later arrivals.
func (q *ClipQueue) add(c *Clip) *Clip {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.seq++
	c.Seq = q.seq
	c.Received = time.Now()
	q.purgeLocked(c.Received)
	q.clips = append(q.clips, c)
	q.bytes += int64(len(c.Data))
	q.trimLocked()
	return c
}

// snapshotSince returns a copy of the clips the recipient has not heard yet, in
// arrival order.
//
// The cursor is supplied by the client and cannot be taken at face value: Seq
// restarts at 1 whenever the hub recreates the queue after dropping an empty
// one, so a cursor left over from a previous queue would hide every clip. A
// cursor outside the range still held by this queue is therefore ignored and
// the caller receives everything available, which is the same as never having
// listened to anything.
func (q *ClipQueue) snapshotSince(cursor int64) []*Clip {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.purgeLocked(time.Now())
	if len(q.clips) == 0 {
		return nil
	}
	first := q.clips[0].Seq
	last := q.clips[len(q.clips)-1].Seq
	if cursor < first-1 || cursor > last {
		cursor = first - 1
	}
	out := make([]*Clip, 0, len(q.clips))
	for _, c := range q.clips {
		if c.Seq > cursor {
			out = append(out, c)
		}
	}
	return out
}

// sweep removes expired clips and returns the number of clips still held. It is
// used by the cleanup loop to drop empty queues.
func (q *ClipQueue) sweep(now time.Time) int {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.purgeLocked(now)
	return len(q.clips)
}

func (q *ClipQueue) purgeLocked(now time.Time) {
	if q.ttl <= 0 {
		return
	}
	cut := now.Add(-q.ttl)
	i := 0
	for ; i < len(q.clips); i++ {
		if q.clips[i].Received.After(cut) {
			break
		}
	}
	q.dropLocked(i)
}

// trimLocked drops the oldest clips until the queue fits both limits. A zero or
// negative limit disables its respective constraint.
func (q *ClipQueue) trimLocked() {
	for len(q.clips) > 0 {
		overCount := q.maxClips > 0 && len(q.clips) > q.maxClips
		overBytes := q.maxBytes > 0 && q.bytes > q.maxBytes
		if !overCount && !overBytes {
			return
		}
		// One at a time: the budget is only re-evaluated against q.bytes after
		// this drop is accounted for.
		q.dropLocked(1)
	}
}

// dropLocked removes the first n clips and keeps bytes in sync. The vacated
// slots are cleared so the clips become collectable: reslicing alone keeps them
// referenced by the backing array, which would defeat the byte budget.
func (q *ClipQueue) dropLocked(n int) {
	for i := 0; i < n; i++ {
		q.bytes -= int64(len(q.clips[i].Data))
		q.clips[i] = nil
	}
	q.clips = q.clips[n:]
}
