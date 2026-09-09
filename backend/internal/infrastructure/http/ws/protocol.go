package ws

import (
	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/user"
)

// Message types sent by the server.
const (
	msgJoined    = "joined"
	msgPeerJoin  = "peer_joined"
	msgPeerLeft  = "peer_left"
	msgOffer     = "offer"
	msgAnswer    = "answer"
	msgICE       = "ice"
	msgTalkStart = "talk_start"
	msgTalkStop  = "talk_stop"
	msgTalkBusy  = "talk_busy"
	msgError     = "error"
)

// Targets of a signaling message.
const (
	targetReceive = "receive"
	targetPublish = "publish"
)

// inboundMessage is a message sent by the client over the WebSocket.
type inboundMessage struct {
	Type      string           `json:"type"`
	Target    string           `json:"target,omitempty"`
	SDP       string           `json:"sdp,omitempty"`
	Candidate *ICECandidateMsg `json:"candidate,omitempty"`
}

// ICECandidateMsg is the wire format for an ICE candidate.
type ICECandidateMsg struct {
	Candidate        string `json:"candidate"`
	SDPMid           string `json:"sdpMid"`
	SDPMLineIndex    uint16 `json:"sdpMLineIndex"`
	UsernameFragment string `json:"usernameFragment,omitempty"`
}

// outboundMessage is a message sent by the server to a client.
type outboundMessage struct {
	Type      string           `json:"type"`
	Target    string           `json:"target,omitempty"`
	SDP       string           `json:"sdp,omitempty"`
	Candidate *ICECandidateMsg `json:"candidate,omitempty"`
	Room      *roomInfo        `json:"room,omitempty"`
	Members   []memberInfo     `json:"members,omitempty"`
	UserID    uuid.UUID        `json:"userId,omitempty"`
	Username  string           `json:"username,omitempty"`
	Message   string           `json:"message,omitempty"`
}

type roomInfo struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
}

type memberInfo struct {
	UserID   uuid.UUID `json:"userId"`
	Username string    `json:"username"`
	Talking  bool      `json:"talking"`
}

func newMemberInfo(u *user.User, talking bool) memberInfo {
	return memberInfo{UserID: u.ID, Username: u.Username, Talking: talking}
}
