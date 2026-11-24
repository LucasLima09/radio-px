package orbit

import (
	"bytes"
	"crypto/ed25519"
	"encoding/hex"
	"testing"
	"time"
)

func testKey(fill byte) ed25519.PrivateKey {
	return ed25519.NewKeyFromSeed(bytes.Repeat([]byte{fill}, ed25519.SeedSize))
}

func testSignal() Signal {
	return Signal{
		DeviceID:  [8]byte{0xA1, 0xB2, 0xC3, 0xD4, 0x01, 0x02, 0x03, 0x04},
		At:        time.Unix(1_790_000_000, 0).UTC(),
		Latitude:  -28.4507437,
		Longitude: -52.199568,
	}
}

func TestSignalRoundTrip(t *testing.T) {
	key := testKey(7)
	raw := testSignal().Sign(key)
	if len(raw) != SignalSize {
		t.Fatalf("len = %d", len(raw))
	}
	got, err := OpenSignal(raw, key.Public().(ed25519.PublicKey))
	if err != nil {
		t.Fatal(err)
	}
	if got != testSignal() {
		t.Fatalf("got %+v", got)
	}
	if got.Identifier() != "A1B2C3D401020304" {
		t.Fatalf("identifier = %s", got.Identifier())
	}
}

// O mesmo vetor está no teste do app (orbit_decoder_test.dart): se o formato
// mudar de um lado só, um dos dois quebra.
func TestSignalVector(t *testing.T) {
	raw := testSignal().Sign(testKey(7))
	if got := hex.EncodeToString(raw); got != signalVector {
		t.Fatalf("vector changed: %s", got)
	}
}

func TestOpenSignalRejects(t *testing.T) {
	key := testKey(7)
	public := key.Public().(ed25519.PublicKey)
	raw := testSignal().Sign(key)
	for i := range raw {
		bad := bytes.Clone(raw)
		bad[i] ^= 1
		if _, err := OpenSignal(bad, public); err != ErrInvalidSignature {
			t.Fatalf("byte %d changed: err = %v", i, err)
		}
	}
	if _, err := OpenSignal(raw, testKey(8).Public().(ed25519.PublicKey)); err != ErrInvalidSignature {
		t.Fatalf("other key: err = %v", err)
	}
	if _, err := OpenSignal(raw[:83], public); err != ErrInvalidSignal {
		t.Fatalf("short: err = %v", err)
	}
}

func TestFragmentsFitLegacyAdvertisement(t *testing.T) {
	raw := testSignal().Sign(testKey(7))
	fragments, err := Fragments(raw)
	if err != nil || len(fragments) != FragmentCount {
		t.Fatalf("fragments = %d, err = %v", len(fragments), err)
	}
	var joined []byte
	for i, f := range fragments {
		// 31 bytes do anúncio menos tamanho(1), tipo(1) e company id(2).
		if len(f) != 27 || f[2] != byte(i) {
			t.Fatalf("fragment %d: % x", i, f)
		}
		joined = append(joined, f[6:]...)
	}
	if !bytes.Equal(joined, raw) {
		t.Fatal("fragments do not rebuild the signal")
	}
}

const signalVector = "a1b2c3d4010203046ab13b80ef0ac2d3e0e2fa60cb975187cf349477a000273722147e25a25e5620daec46de0295c731ca5143a7a1b55b9d392465a4a8d3547c49bc65ef0c7153c8f6fdc2b05ae4e6d2fc848409"
