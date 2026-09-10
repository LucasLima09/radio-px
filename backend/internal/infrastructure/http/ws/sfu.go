package ws

import (
	"context"
	"log/slog"
	"strings"

	"github.com/pion/rtp"
	"github.com/pion/webrtc/v4"
)

// logCandidate logs an ICE candidate for diagnostics. A nil candidate means
// ICE gathering completed.
func logCandidate(role string, c *webrtc.ICECandidate, user string) {
	if c == nil {
		slog.Info("gather complete", "role", role, "user", user)
		return
	}
	slog.Info("candidate",
		"role", role,
		"user", user,
		"type", c.Typ.String(),
		"proto", c.Protocol.String(),
		"addr", c.Address,
		"port", c.Port,
	)
}

func newPeerConnection(stunServers []string) (*webrtc.PeerConnection, error) {
	iceServers := make([]webrtc.ICEServer, 0, len(stunServers))
	for _, s := range stunServers {
		if s = strings.TrimSpace(s); s != "" {
			iceServers = append(iceServers, webrtc.ICEServer{URLs: []string{s}})
		}
	}

	return webrtc.NewPeerConnection(webrtc.Configuration{
		ICEServers: iceServers,
	})
}

// localTrack couples a fan-out local track with the RTP sender bound on a
// listener peer connection, so it can be removed when the talk session ends.
type localTrack struct {
	local  *webrtc.TrackLocalStaticRTP
	sender *webrtc.RTPSender
}

// wireCandidate converts a pion ICE candidate into the wire format. A nil
// candidate signals that ICE gathering completed.
func wireCandidate(c *webrtc.ICECandidate) *ICECandidateMsg {
	if c == nil {
		return &ICECandidateMsg{}
	}
	init := c.ToJSON()
	msg := &ICECandidateMsg{
		Candidate: init.Candidate,
	}
	if init.SDPMid != nil {
		msg.SDPMid = *init.SDPMid
	}
	if init.UsernameFragment != nil {
		msg.UsernameFragment = *init.UsernameFragment
	}
	if init.SDPMLineIndex != nil {
		msg.SDPMLineIndex = *init.SDPMLineIndex
	}
	return msg
}

func toICECandidateInit(m *ICECandidateMsg) webrtc.ICECandidateInit {
	return webrtc.ICECandidateInit{
		Candidate:        m.Candidate,
		SDPMid:           &m.SDPMid,
		UsernameFragment: &m.UsernameFragment,
		SDPMLineIndex:    &m.SDPMLineIndex,
	}
}

func newFanOutTrack(source *webrtc.TrackRemote) (*webrtc.TrackLocalStaticRTP, error) {
	return webrtc.NewTrackLocalStaticRTP(
		source.Codec().RTPCodecCapability,
		source.ID(),
		"radio-px",
	)
}

// startForwarder reads RTP packets from the publisher track and writes them
// to every fan-out track. locals is evaluated on every packet so members that
// join while a talk is in progress start receiving immediately. Calling the
// returned cancel stops the loop; the publisher peer connection must be closed
// to unblock an ongoing read.
func startForwarder(ctx context.Context, source *webrtc.TrackRemote, locals func() []*webrtc.TrackLocalStaticRTP) context.CancelFunc {
	ctx, cancel := context.WithCancel(ctx)
	go func() {
		defer cancel()
		for {
			pkt, _, err := source.ReadRTP()
			if err != nil {
				return
			}
			p := clonePacket(pkt)
			ls := locals()
			for _, loc := range ls {
				_ = loc.WriteRTP(p)
			}
		}
	}()
	return cancel
}

func clonePacket(pkt *rtp.Packet) *rtp.Packet {
	p := *pkt
	p.Payload = append([]byte(nil), pkt.Payload...)
	p.Header.CSRC = append([]uint32(nil), pkt.Header.CSRC...)
	return &p
}
