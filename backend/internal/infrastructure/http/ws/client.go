package ws

import (
	"context"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	"github.com/pion/webrtc/v4"
)

var errNoReceivePeer = errors.New("receive peer connection is not ready")

// recvSignaling serializes server-initiated renegotiation of the receive peer
// connection. Only one offer may be in flight at a time; requests received
// while an answer is pending set the dirty flag so a follow-up offer is sent
// as soon as the pending answer arrives.
type recvSignaling struct {
	pc           *webrtc.PeerConnection
	mu           sync.Mutex
	pendingOffer bool
	dirty        bool
}

type Client struct {
	room        *Room
	user        *user.User
	stunServers []string

	sendCh chan []byte
	done   chan struct{}

	conn *websocket.Conn

	recv *recvSignaling

	pubMu     sync.Mutex
	publishPC *webrtc.PeerConnection

	closeOnce sync.Once
}

func newClient(room *Room, u *user.User, conn *websocket.Conn, stunServers []string) *Client {
	return &Client{
		room:        room,
		user:        u,
		stunServers: stunServers,
		sendCh:      make(chan []byte, 128),
		done:        make(chan struct{}),
		conn:        conn,
		recv:        &recvSignaling{},
	}
}

func (c *Client) send(m outboundMessage) {
	data, err := json.Marshal(m)
	if err != nil {
		return
	}
	select {
	case c.sendCh <- data:
	default:
	}
}

func (c *Client) sendError(message string) {
	c.send(outboundMessage{Type: msgError, Message: message})
}

// setupReceivePC creates the persistent receive peer connection used to listen
// to the channel feed and sends the initial offer to the client. An audio
// transceiver is reserved up front so the offer carries a real media section
// (ICE credentials live on media lines; a media-less offer is rejected by
// clients).
func (c *Client) setupReceivePC() error {
	pc, err := newPeerConnection(c.stunServers)
	if err != nil {
		return err
	}
	if _, err := pc.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RTPTransceiverInit{
		Direction: webrtc.RTPTransceiverDirectionSendonly,
	}); err != nil {
		_ = pc.Close()
		return err
	}
	pc.OnICECandidate(func(cand *webrtc.ICECandidate) {
		c.send(outboundMessage{Type: msgICE, Target: targetReceive, Candidate: wireCandidate(cand)})
	})
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		if state == webrtc.PeerConnectionStateFailed || state == webrtc.PeerConnectionStateClosed {
			c.close()
		}
	})

	c.recv.mu.Lock()
	if c.recv.pc != nil {
		_ = c.recv.pc.Close()
	}
	c.recv.pc = pc
	c.recv.pendingOffer = true
	c.recv.mu.Unlock()

	c.sendRecvOffer()
	return nil
}

func (c *Client) sendRecvOffer() {
	offer, err := c.recv.pc.CreateOffer(nil)
	if err != nil {
		c.sendError("failed to create receive offer")
		return
	}
	if err := c.recv.pc.SetLocalDescription(offer); err != nil {
		c.sendError("failed to set local description")
		return
	}
	c.send(outboundMessage{Type: msgOffer, Target: targetReceive, SDP: offer.SDP})
}

func (c *Client) renegotiateRecv() {
	c.recv.mu.Lock()
	if c.recv.pendingOffer {
		c.recv.dirty = true
		c.recv.mu.Unlock()
		return
	}
	c.recv.pendingOffer = true
	pc := c.recv.pc
	c.recv.mu.Unlock()

	if pc == nil {
		return
	}
	offer, err := pc.CreateOffer(nil)
	if err != nil {
		return
	}
	if err := pc.SetLocalDescription(offer); err != nil {
		return
	}
	c.send(outboundMessage{Type: msgOffer, Target: targetReceive, SDP: offer.SDP})
}

func (c *Client) handleRecvAnswer(sdp string) {
	c.recv.mu.Lock()
	pc := c.recv.pc
	c.recv.pendingOffer = false
	dirty := c.recv.dirty
	c.recv.dirty = false
	c.recv.mu.Unlock()

	if pc == nil {
		return
	}
	if err := pc.SetRemoteDescription(webrtc.SessionDescription{Type: webrtc.SDPTypeAnswer, SDP: sdp}); err != nil {
		return
	}
	if dirty {
		c.renegotiateRecv()
	}
}

func (c *Client) addFanOutTrack(local *webrtc.TrackLocalStaticRTP) (*webrtc.RTPSender, error) {
	c.recv.mu.Lock()
	defer c.recv.mu.Unlock()
	pc := c.recv.pc
	if pc == nil {
		return nil, errNoReceivePeer
	}
	return pc.AddTrack(local)
}

func (c *Client) removeFanOutTrack(t *localTrack) error {
	c.recv.mu.Lock()
	defer c.recv.mu.Unlock()
	if c.recv.pc == nil || t.sender == nil {
		return nil
	}
	return c.recv.pc.RemoveTrack(t.sender)
}

// handlePublishOffer handles a client offer of a publish (PTT) peer connection.
func (c *Client) handlePublishOffer(sdp string) {
	c.pubMu.Lock()
	defer c.pubMu.Unlock()

	pc, err := newPeerConnection(c.stunServers)
	if err != nil {
		c.sendError("failed to create publish peer connection")
		return
	}
	pc.OnICECandidate(func(cand *webrtc.ICECandidate) {
		c.send(outboundMessage{Type: msgICE, Target: targetPublish, Candidate: wireCandidate(cand)})
	})
	pc.OnTrack(func(track *webrtc.TrackRemote, _ *webrtc.RTPReceiver) {
		if err := c.room.startTalk(c, track); err != nil {
			if errors.Is(err, errTalkBusy) {
				c.send(outboundMessage{Type: msgTalkBusy})
			}
			c.closePublishPCLocked()
			return
		}
	})
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		if !terminalState(state) {
			return
		}
		c.pubMu.Lock()
		active := c.publishPC == pc
		c.pubMu.Unlock()
		if active {
			c.room.stopTalk(c)
		}
	})

	if err := pc.SetRemoteDescription(webrtc.SessionDescription{Type: webrtc.SDPTypeOffer, SDP: sdp}); err != nil {
		_ = pc.Close()
		return
	}
	answer, err := pc.CreateAnswer(nil)
	if err != nil {
		_ = pc.Close()
		return
	}
	if err := pc.SetLocalDescription(answer); err != nil {
		_ = pc.Close()
		return
	}

	c.closePublishPCLocked()
	c.publishPC = pc
	c.send(outboundMessage{Type: msgAnswer, Target: targetPublish, SDP: answer.SDP})
}

func (c *Client) handlePublishICE(init webrtc.ICECandidateInit) {
	c.pubMu.Lock()
	defer c.pubMu.Unlock()
	if c.publishPC != nil {
		_ = c.publishPC.AddICECandidate(init)
	}
}

func (c *Client) closePublishPC() {
	c.pubMu.Lock()
	defer c.pubMu.Unlock()
	c.closePublishPCLocked()
}

func (c *Client) closePublishPCLocked() {
	if c.publishPC != nil {
		_ = c.publishPC.Close()
		c.publishPC = nil
	}
}

func terminalState(state webrtc.PeerConnectionState) bool {
	return state == webrtc.PeerConnectionStateFailed ||
		state == webrtc.PeerConnectionStateClosed
}

// writePump serializes writes to the WebSocket connection.
func (c *Client) writePump() {
	for {
		select {
		case <-c.done:
			return
		case msg := <-c.sendCh:
			writeCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			err := c.conn.Write(writeCtx, websocket.MessageText, msg)
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
		c.recv.mu.Lock()
		if c.recv.pc != nil {
			_ = c.recv.pc.Close()
			c.recv.pc = nil
		}
		c.recv.mu.Unlock()
		c.closePublishPC()
		_ = c.conn.Close(websocket.StatusNormalClosure, "bye")
	})
}

// handle processes a single inbound signaling message.
func (c *Client) handle(m *inboundMessage) {
	switch m.Type {
	case "answer":
		if m.Target == targetReceive {
			c.handleRecvAnswer(m.SDP)
		}
	case "offer":
		if m.Target == targetPublish {
			c.handlePublishOffer(m.SDP)
		}
	case "ice":
		if m.Candidate == nil {
			return
		}
		init := toICECandidateInit(m.Candidate)
		if m.Target == targetReceive {
			c.recv.mu.Lock()
			pc := c.recv.pc
			c.recv.mu.Unlock()
			if pc != nil {
				_ = pc.AddICECandidate(init)
			}
		} else if m.Target == targetPublish {
			c.handlePublishICE(init)
		}
	case "talk_stop":
		c.room.stopTalk(c)
	case "leave":
		c.close()
	}
}

// readLoop reads inbound messages until the connection is closed.
func (c *Client) readLoop() {
	defer c.close()
	c.conn.SetReadLimit(1 << 20)
	for {
		typ, data, err := c.conn.Read(context.Background())
		if err != nil {
			return
		}
		if typ != websocket.MessageText && typ != websocket.MessageBinary {
			continue
		}
		var m inboundMessage
		if err := json.Unmarshal(data, &m); err != nil {
			c.sendError("invalid message")
			continue
		}
		c.handle(&m)
	}
}
