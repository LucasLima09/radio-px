package orbit

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"math"
	"strings"
	"time"
)

// Sinal que o Orbit transmite por BLE (big-endian):
//
//	id(8) | hora unix em s(4) | lat×1e7(4) | lng×1e7(4) | assinatura Ed25519(64)
//
// São 84 bytes, que não cabem em um anúncio BLE comum (31). Vão divididos em 4
// anúncios, no manufacturer data de CompanyID:
//
//	magic 'O'(1) | versão(1) | índice(1) | tag(3) | pedaço(21)
//
// A tag são os 3 primeiros bytes da assinatura e diz quais pedaços são do
// mesmo sinal. O app junta os 4, confere a assinatura com a chave pública e
// repassa os 84 bytes; o servidor confere de novo.
const (
	// CompanyID 0xFFFF é reservado pelo Bluetooth SIG para testes.
	CompanyID = 0xFFFF

	DeviceIDSize  = 8
	FragmentCount = 4

	fragmentMagic   = 'O'
	fragmentVersion = 1
	fragmentChunk   = 21
	bodySize        = DeviceIDSize + 4 + 4 + 4

	SignalSize = bodySize + ed25519.SignatureSize
)

// Prefixo do que é assinado: impede reaproveitar a assinatura em outro
// contexto. O app usa o mesmo.
const signatureContext = "radiopx-orbit-v1"

var (
	ErrInvalidSignal    = errors.New("invalid orbit signal")
	ErrInvalidSignature = errors.New("invalid orbit signature")
	ErrInvalidKey       = errors.New("invalid orbit public key")
)

// Signal é o conteúdo do sinal: tudo aqui veio do próprio Orbit.
type Signal struct {
	DeviceID  [DeviceIDSize]byte
	At        time.Time
	Latitude  float64
	Longitude float64
}

// Identifier é o id do dispositivo em hexadecimal.
func (s Signal) Identifier() string {
	return strings.ToUpper(hex.EncodeToString(s.DeviceID[:]))
}

// Sign monta e assina os 84 bytes do sinal.
func (s Signal) Sign(key ed25519.PrivateKey) []byte {
	out := make([]byte, bodySize, SignalSize)
	copy(out, s.DeviceID[:])
	binary.BigEndian.PutUint32(out[8:], uint32(s.At.Unix()))
	binary.BigEndian.PutUint32(out[12:], uint32(int32(math.Round(s.Latitude*1e7))))
	binary.BigEndian.PutUint32(out[16:], uint32(int32(math.Round(s.Longitude*1e7))))
	return append(out, ed25519.Sign(key, signedBytes(out))...)
}

// OpenSignal confere a assinatura e devolve o conteúdo do sinal.
func OpenSignal(raw []byte, key ed25519.PublicKey) (Signal, error) {
	if len(raw) != SignalSize {
		return Signal{}, ErrInvalidSignal
	}
	body, signature := raw[:bodySize], raw[bodySize:]
	if !ed25519.Verify(key, signedBytes(body), signature) {
		return Signal{}, ErrInvalidSignature
	}
	var s Signal
	copy(s.DeviceID[:], body)
	s.At = time.Unix(int64(binary.BigEndian.Uint32(body[8:])), 0).UTC()
	s.Latitude = float64(int32(binary.BigEndian.Uint32(body[12:]))) / 1e7
	s.Longitude = float64(int32(binary.BigEndian.Uint32(body[16:]))) / 1e7
	return s, nil
}

// Fragments divide o sinal nos dados de fabricante de cada anúncio BLE.
func Fragments(raw []byte) ([][]byte, error) {
	if len(raw) != SignalSize {
		return nil, ErrInvalidSignal
	}
	tag := raw[bodySize : bodySize+3]
	out := make([][]byte, 0, FragmentCount)
	for i := range FragmentCount {
		fragment := []byte{fragmentMagic, fragmentVersion, byte(i)}
		fragment = append(fragment, tag...)
		fragment = append(fragment, raw[i*fragmentChunk:(i+1)*fragmentChunk]...)
		out = append(out, fragment)
	}
	return out, nil
}

// ParsePublicKey lê a chave pública em base64.
func ParsePublicKey(s string) (ed25519.PublicKey, error) {
	key, err := base64.StdEncoding.DecodeString(strings.TrimSpace(s))
	if err != nil || len(key) != ed25519.PublicKeySize {
		return nil, ErrInvalidKey
	}
	return ed25519.PublicKey(key), nil
}

func signedBytes(body []byte) []byte {
	return append([]byte(signatureContext), body...)
}
