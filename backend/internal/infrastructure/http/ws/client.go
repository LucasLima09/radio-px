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

// outboundFrame is a single entry queued for a client: either a text (JSON
// signaling) message or a whole audio clip. A clip takes one slot and is
// chunked only by writePump, so its metadata and payload always go out
// together and contiguous.
type outboundFrame struct {
	Kind websocket.MessageType
	Data []byte
	Clip *Clip
}

const (
	frameText   = websocket.MessageText
	frameBinary = websocket.MessageBinary
)

// clipPayloadChunk is the maximum binary frame size pushed to a client.
const clipPayloadChunk = 32 << 10

// minSendQueue is the smallest outbound queue per client. The queue must also
// fit a full clip snapshot on join, see newClient.
const minSendQueue = 256

const (
	pingInterval = 25 * time.Second
	pingTimeout  = 10 * time.Second
	writeTimeout = 10 * time.Second
)

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
	slowOnce  sync.Once
}

func newClient(room *Room, u *user.User, conn *websocket.Conn, locations location.Repository) *Client {
	queueSize := minSendQueue
	if room != nil && room.hub != nil && room.hub.maxClips+64 > queueSize {
		queueSize = room.hub.maxClips + 64
	}
	return &Client{
		room:      room,
		user:      u,
		locations: locations,
		sendCh:    make(chan outboundFrame, queueSize),
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

// pushFrame enqueues a frame without blocking the caller, which often holds
// the room lock. A full queue means the client cannot keep up: silently
// dropping frames would leave it with missing audio or stale presence, so the
// connection is dropped instead. The app reconnects with last_heard_seq and
// receives whatever it missed from the clip queue.
func (c *Client) pushFrame(f outboundFrame) {
	select {
	case c.sendCh <- f:
	default:
		c.dropSlow()
	}
}

// dropSlow closes the connection of a client whose queue overflowed. It runs
// the close in a goroutine because pushFrame may be called with the room lock
// held, and close needs that lock to remove the client.
func (c *Client) dropSlow() {
	c.slowOnce.Do(func() {
		slog.Warn("dropping slow websocket client", "user", c.user.Username)
		if c.conn == nil {
			return
		}
		go func() {
			_ = c.conn.Close(websocket.StatusTryAgainLater, "client too slow")
		}()
	})
}

// sendClip publishes a clip to this client as a single queue entry; writePump
// sends the clip_new metadata followed by the binary payload.
func (c *Client) sendClip(clip *Clip) {
	c.pushFrame(outboundFrame{Clip: clip})
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
	maxBytes := c.room.hub.maxClipBytes
	if maxBytes <= 0 {
		maxBytes = defaultMaxClipBytes
	}
	if m.ClipID == "" || m.Size <= 0 || m.Size > maxBytes {
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
	loc, err := location.New(c.user.ID, &c.room.id, *lat, *lng)
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
			var err error
			if f.Clip != nil {
				err = c.writeClip(f.Clip)
			} else {
				err = c.write(f.Kind, f.Data)
			}
			if err != nil {
				// Unblock readLoop so the client is removed from the room.
				_ = c.conn.CloseNow()
				return
			}
		}
	}
}

func (c *Client) write(kind websocket.MessageType, data []byte) error {
	ctx, cancel := context.WithTimeout(context.Background(), writeTimeout)
	defer cancel()
	return c.conn.Write(ctx, kind, data)
}

// writeClip sends the clip_new metadata and then the payload in chunks.
func (c *Client) writeClip(clip *Clip) error {
	meta, err := json.Marshal(outboundMessage{Type: msgClipNew, Clip: ptr(clip.info())})
	if err != nil {
		return nil
	}
	if err := c.write(frameText, meta); err != nil {
		return err
	}
	data := clip.Data
	for off := 0; off < len(data); off += clipPayloadChunk {
		end := min(off+clipPayloadChunk, len(data))
		if err := c.write(frameBinary, data[off:end]); err != nil {
			return err
		}
	}
	return nil
}

// pingLoop detects dead connections (a phone that lost signal never sends a
// close frame). Without it the member would stay online, with a stale marker
// on the map, until the TCP connection times out.
func (c *Client) pingLoop() {
	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()
	for {
		select {
		case <-c.done:
			return
		case <-ticker.C:
			ctx, cancel := context.WithTimeout(context.Background(), pingTimeout)
			err := c.conn.Ping(ctx)
			cancel()
			if err != nil {
				_ = c.conn.CloseNow()
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
