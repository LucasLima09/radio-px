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
type ClipQueue struct {
	mu           sync.Mutex
	ttl          time.Duration
	maxClips     int
	maxClipBytes int64
	seq          int64
	clips        []*Clip
}

func newClipQueue(ttl time.Duration, maxClips int, maxClipBytes int64) *ClipQueue {
	return &ClipQueue{
		ttl:          ttl,
		maxClips:     maxClips,
		maxClipBytes: maxClipBytes,
	}
}

// add appends a clip to the queue, assigning its sequence number (arrival
// order) and trimming the queue when it exceeds maxClips.
func (q *ClipQueue) add(c *Clip) *Clip {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.seq++
	c.Seq = q.seq
	c.Received = time.Now()
	q.purgeLocked(c.Received)
	q.clips = append(q.clips, c)
	if q.maxClips > 0 && len(q.clips) > q.maxClips {
		q.clips = append([]*Clip(nil), q.clips[len(q.clips)-q.maxClips:]...)
	}
	return c
}

// snapshot returns a copy of the still-valid clips in arrival order.
func (q *ClipQueue) snapshot() []*Clip {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.purgeLocked(time.Now())
	out := make([]*Clip, len(q.clips))
	copy(out, q.clips)
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
	if i > 0 {
		q.clips = append([]*Clip(nil), q.clips[i:]...)
	}
}
