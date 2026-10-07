package ws

import (
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/user"
)

// Message types sent by the server.
const (
	msgJoined         = "joined"
	msgPeerJoin       = "peer_joined"
	msgPeerLeft       = "peer_left"
	msgClipNew        = "clip_new"
	msgRecordingStart = "recording_start"
	msgRecordingStop  = "recording_stop"
	msgError          = "error"
)

// Message types received from the client. recording_start/recording_stop are
// shared with the server in the opposite direction.
const (
	msgClipStart = "clip_start"
	msgClipEnd   = "clip_end"
	msgLeave     = "leave"
)

// maxClipDuration is the maximum length allowed for a single audio clip.
const maxClipDuration = 60 * time.Second

// defaultMaxClipBytes is the per-clip upload limit used when the hub carries no
// positive CLIP_MAX_BYTES configuration.
const defaultMaxClipBytes = 5 << 20

// inboundMessage is a message sent by the client over the WebSocket.
type inboundMessage struct {
	Type       string `json:"type"`
	ClipID     string `json:"clipId,omitempty"`
	MIME       string `json:"mime,omitempty"`
	DurationMS int64  `json:"durationMs,omitempty"`
	Size       int64  `json:"size,omitempty"`
}

// outboundMessage is a message sent by the server to a client.
type outboundMessage struct {
	Type     string       `json:"type"`
	Room     *roomInfo    `json:"room,omitempty"`
	Members  []memberInfo `json:"members,omitempty"`
	UserID   uuid.UUID    `json:"userId,omitempty"`
	Username string       `json:"username,omitempty"`
	Message  string       `json:"message,omitempty"`
	Clip     *clipInfo    `json:"clip,omitempty"`
}

type roomInfo struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
}

type memberInfo struct {
	UserID    uuid.UUID `json:"userId"`
	Username  string    `json:"username"`
	Recording bool      `json:"recording"`
}

// clipInfo is the metadata of an audio clip broadcast as clip_new. The binary
// payload is sent right after this message, in one or more binary frames.
type clipInfo struct {
	ClipID     uuid.UUID `json:"clipId"`
	UserID     uuid.UUID `json:"userId"`
	Username   string    `json:"username"`
	MIME       string    `json:"mime"`
	DurationMS int64     `json:"durationMs"`
	Seq        int64     `json:"seq"`
	Size       int64     `json:"size"`
}

func newMemberInfo(u *user.User, recording bool) memberInfo {
	return memberInfo{UserID: u.ID, Username: u.Username, Recording: recording}
}
