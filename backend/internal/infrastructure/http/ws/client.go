package ws

import (
	"context"
	"encoding/json"
	"log/slog"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/location"
	"github.com/lucas/radio-px-backend/internal/domain/user"
)

// outboundFrame is a single frame queued for a client: either a text (JSON
// signaling) message or a binary chunk of an audio clip payload.
type outboundFrame struct {
	Kind websocket.MessageType
	Data []byte
}

const (
	frameText   = websocket.MessageText
	frameBinary = websocket.MessageBinary
)

// clipPayloadChunk is the maximum binary frame size pushed to a client.
const clipPayloadChunk = 32 << 10

const maxUploadSize = 5 << 20 // 5 MiB per clip

// pendingClip assembles an audio clip being uploaded by the client over a
// stream of binary frames.
type pendingClip struct {
	id       string
	mime     string
	duration time.Duration
	size     int64
	data     []byte
}

type Client struct {
	room      *Room
	user      *user.User
	locations location.Repository

	sendCh chan outboundFrame
	done   chan struct{}

	conn *websocket.Conn

	pending *pendingClip

	closeOnce sync.Once
}

func newClient(room *Room, u *user.User, conn *websocket.Conn, locations location.Repository) *Client {
	return &Client{
		room:      room,
		user:      u,
		locations: locations,
		sendCh:    make(chan outboundFrame, 256),
		done:      make(chan struct{}),
		conn:      conn,
	}
}

func (c *Client) send(m outboundMessage) {
	data, err := json.Marshal(m)
	if err != nil {
		return
	}
	c.pushFrame(outboundFrame{Kind: frameText, Data: data})
}

func (c *Client) sendError(message string) {
	c.send(outboundMessage{Type: msgError, Message: message})
}

// pushFrame enqueues a frame without blocking the read loop. A full queue
// drops the frame (best effort under load).
func (c *Client) pushFrame(f outboundFrame) {
	select {
	case c.sendCh <- f:
	default:
	}
}

// sendClip publishes a clip to this client: the clip_new metadata message
// followed by the binary payload. If the metadata cannot be queued nothing is
// sent, so a payload never arrives without its header.
func (c *Client) sendClip(clip *Clip) {
	meta, err := json.Marshal(outboundMessage{Type: msgClipNew, Clip: ptr(clip.info())})
	if err != nil {
		return
	}
	c.pushFrame(outboundFrame{Kind: frameText, Data: meta})
	data := clip.Data
	for off := 0; off < len(data); off += clipPayloadChunk {
		end := off + clipPayloadChunk
		if end > len(data) {
			end = len(data)
		}
		c.pushFrame(outboundFrame{Kind: frameBinary, Data: data[off:end]})
	}
}

func ptr[T any](v T) *T { return &v }

// handle processes a single inbound text message.
func (c *Client) handle(m *inboundMessage) {
	switch m.Type {
	case msgClipStart:
		c.handleClipStart(m)
	case msgClipEnd:
		c.handleClipEnd(m)
	case msgRecordingStart:
		c.room.setRecording(c, true)
	case msgRecordingStop:
		c.room.setRecording(c, false)
	case msgLocation:
		c.handleLocation(m.Lat, m.Lng)
	case msgLeave:
		c.close()
	}
}

// handleClipPayload appends an inbound binary frame to the clip being uploaded.
func (c *Client) handleClipPayload(data []byte) {
	p := c.pending
	if p == nil {
		return
	}
	if int64(len(p.data)+len(data)) > p.size {
		c.sendError("clip payload larger than declared size")
		c.pending = nil
		return
	}
	p.data = append(p.data, data...)
}

func (c *Client) handleClipStart(m *inboundMessage) {
	if m.ClipID == "" || m.Size <= 0 || m.Size > maxUploadSize {
		c.sendError("invalid clip metadata")
		return
	}
	if m.DurationMS <= 0 || time.Duration(m.DurationMS)*time.Millisecond > maxClipDuration {
		c.sendError("clip duration exceeds the limit")
		return
	}
	c.pending = &pendingClip{
		id:       m.ClipID,
		mime:     m.MIME,
		duration: time.Duration(m.DurationMS) * time.Millisecond,
		size:     m.Size,
	}
}

func (c *Client) handleClipEnd(m *inboundMessage) {
	p := c.pending
	if p == nil || p.id != m.ClipID {
		c.sendError("no clip upload in progress")
		return
	}
	c.pending = nil
	if int64(len(p.data)) != p.size {
		c.sendError("clip payload does not match declared size")
		return
	}

	id, err := uuid.Parse(p.id)
	if err != nil {
		id = uuid.New()
	}
	clip := &Clip{
		ID:       id,
		UserID:   c.user.ID,
		Username: c.user.Username,
		MIME:     p.mime,
		Duration: p.duration,
		Data:     p.data,
	}
	q := c.room.hub.queueFor(c.room.id)
	q.add(clip)
	c.room.broadcastClip(clip)
}

// handleLocation updates the member position in the room and persists it to
// the database without blocking the WebSocket read loop.
func (c *Client) handleLocation(lat, lng *float64) {
	if lat == nil || lng == nil {
		c.sendError("invalid location")
		return
	}
	loc, err := location.New(c.user.ID, c.room.id, *lat, *lng)
	if err != nil {
		c.sendError("invalid location")
		return
	}
	c.room.updateLocation(c, *lat, *lng)
	if c.locations == nil {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		if err := c.locations.Save(ctx, loc); err != nil {
			slog.Warn("persisting location", "user", c.user.Username, "error", err)
		}
	}()
}

// writePump serializes writes to the WebSocket connection.
func (c *Client) writePump() {
	for {
		select {
		case <-c.done:
			return
		case f := <-c.sendCh:
			writeCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			err := c.conn.Write(writeCtx, f.Kind, f.Data)
			cancel()
			if err != nil {
				return
			}
		}
	}
}

func (c *Client) close() {
	c.closeOnce.Do(func() {
		close(c.done)
		c.room.remove(c)
		_ = c.conn.Close(websocket.StatusNormalClosure, "bye")
	})
}

// readLoop reads inbound messages until the connection is closed.
func (c *Client) readLoop() {
	defer c.close()
	c.conn.SetReadLimit(8 << 20)
	for {
		typ, data, err := c.conn.Read(context.Background())
		if err != nil {
			return
		}
		switch typ {
		case websocket.MessageBinary:
			c.handleClipPayload(data)
		case websocket.MessageText:
			var m inboundMessage
			if err := json.Unmarshal(data, &m); err != nil {
				c.sendError("invalid message")
				continue
			}
			c.handle(&m)
		}
	}
}
