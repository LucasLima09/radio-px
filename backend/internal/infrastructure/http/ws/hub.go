package ws

import (
	"log/slog"
	"sync"

	"github.com/google/uuid"
)

type Hub struct {
	logger      *slog.Logger
	stunServers []string

	mu    sync.RWMutex
	rooms map[uuid.UUID]*Room
}

func NewHub(logger *slog.Logger, stunServers []string) *Hub {
	return &Hub{
		logger:      logger,
		stunServers: stunServers,
		rooms:       make(map[uuid.UUID]*Room),
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
