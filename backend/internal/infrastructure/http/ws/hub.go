package ws

import (
	"log/slog"
	"sync"
	"time"

	"github.com/google/uuid"
)

type Hub struct {
	logger        *slog.Logger
	clipTTL       time.Duration
	maxClips      int
	maxClipBytes  int64
	maxQueueBytes int64

	mu     sync.RWMutex
	rooms  map[uuid.UUID]*Room
	queues map[uuid.UUID]*ClipQueue

	cleanupDone chan struct{}
}

func NewHub(logger *slog.Logger, clipTTL time.Duration, maxClips int, maxClipBytes, maxQueueBytes int64) *Hub {
	h := &Hub{
		logger:        logger,
		clipTTL:       clipTTL,
		maxClips:      maxClips,
		maxClipBytes:  maxClipBytes,
		maxQueueBytes: maxQueueBytes,

		rooms:       make(map[uuid.UUID]*Room),
		queues:      make(map[uuid.UUID]*ClipQueue),
		cleanupDone: make(chan struct{}),
	}
	go h.cleanupLoop()
	return h
}

// Stop stops the background clip cleanup loop. Mainly useful for tests.
func (h *Hub) Stop() {
	select {
	case <-h.cleanupDone:
	default:
		close(h.cleanupDone)
	}
}

func (h *Hub) getOrCreateRoom(id uuid.UUID, name string) *Room {
	h.mu.Lock()
	defer h.mu.Unlock()
	room, ok := h.rooms[id]
	if !ok {
		room = newRoom(h, id, name)
		h.rooms[id] = room
	}
	return room
}

func (h *Hub) removeRoom(id uuid.UUID) {
	h.mu.Lock()
	delete(h.rooms, id)
	h.mu.Unlock()
}

// queueFor returns the persistent clip queue of a channel, creating it lazily.
// Queues survive rooms becoming empty so recent clips stay available for
// members who join later (until they expire).
func (h *Hub) queueFor(id uuid.UUID) *ClipQueue {
	h.mu.Lock()
	defer h.mu.Unlock()
	q, ok := h.queues[id]
	if !ok {
		q = newClipQueue(h.clipTTL, h.maxClips, h.maxQueueBytes)
		h.queues[id] = q
	}
	return q
}

func (h *Hub) cleanupLoop() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-h.cleanupDone:
			return
		case now := <-ticker.C:
			h.cleanupQueues(now)
		}
	}
}

func (h *Hub) cleanupQueues(now time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for id, q := range h.queues {
		if q.sweep(now) == 0 {
			delete(h.queues, id)
		}
	}
}
