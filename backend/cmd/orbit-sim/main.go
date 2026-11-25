// Command orbit-sim faz este computador (Linux, BlueZ) se comportar como um
// Orbit: transmite por BLE o sinal assinado com id, hora e localização.
package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/lucas/radio-px-backend/internal/domain/orbit"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		os.Exit(1)
	}
}

func run() error {
	lat := flag.Float64("lat", -28.4507437, "latitude transmitida")
	lng := flag.Float64("lng", -52.199568, "longitude transmitida")
	id := flag.String("id", "", "id do Orbit, 16 dígitos hexadecimais (padrão: o salvo na identidade)")
	every := flag.Duration("every", 30*time.Second, "intervalo entre sinais novos")
	adapter := flag.String("adapter", "hci0", "adaptador Bluetooth")
	forge := flag.Bool("forge", false, "assina com uma chave falsa, para testar a recusa no app")
	dryRun := flag.Bool("dry-run", false, "só mostra um sinal, sem transmitir")
	defaultIdentity, err := identityPath()
	if err != nil {
		return err
	}
	file := flag.String("identity", defaultIdentity, "arquivo com o id e a chave privada")
	flag.Parse()

	if *lat < -90 || *lat > 90 || *lng < -180 || *lng > 180 {
		return errors.New("latitude ou longitude fora do limite")
	}
	if *every < 5*time.Second || *every > time.Minute {
		return errors.New("-every precisa ser de 5s a 1m")
	}

	device, key, err := loadIdentity(*file)
	if err != nil {
		return err
	}
	if *id != "" {
		if device, err = parseDeviceID(*id); err != nil {
			return err
		}
	}
	// Mostrada sempre a chave verdadeira: é a que a central conhece.
	public := base64.StdEncoding.EncodeToString(key.Public().(ed25519.PublicKey))
	if *forge {
		if _, key, err = ed25519.GenerateKey(rand.Reader); err != nil {
			return err
		}
	}

	next := func() orbit.Signal {
		return orbit.Signal{DeviceID: device, At: time.Now(), Latitude: *lat, Longitude: *lng}
	}
	fmt.Printf("Orbit       %s\n", next().Identifier())
	fmt.Printf("Posição     %.7f, %.7f\n", *lat, *lng)
	fmt.Printf("Identidade  %s\n", *file)
	fmt.Printf("\nNo backend/.env:\nORBIT_PUBLIC_KEY=%s\n\n", public)
	if *forge {
		fmt.Print("ASSINATURA FALSA: o app deve ignorar este sinal.\n\n")
	}

	if *dryRun {
		raw := next().Sign(key)
		fragments, err := orbit.Fragments(raw)
		if err != nil {
			return err
		}
		fmt.Printf("Sinal (base64): %s\n", base64.StdEncoding.EncodeToString(raw))
		for i, f := range fragments {
			fmt.Printf("Anúncio %d: %s\n", i+1, hex.EncodeToString(f))
		}
		return nil
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	radio, err := openRadio(*adapter)
	if err != nil {
		return err
	}
	defer radio.Close()

	fmt.Println("Transmitindo. Ctrl+C para parar.")
	ticker := time.NewTicker(*every)
	defer ticker.Stop()
	for {
		s := next()
		fragments, err := orbit.Fragments(s.Sign(key))
		if err != nil {
			return err
		}
		if err := radio.Transmit(fragments); err != nil {
			return err
		}
		fmt.Printf("%s  sinal no ar (%d anúncios × %d)\n", s.At.Format("15:04:05"), len(fragments), radio.copies)
		select {
		case <-ctx.Done():
			fmt.Println("\nEncerrado.")
			return nil
		case <-ticker.C:
		}
	}
}

type identity struct {
	DeviceID string `json:"deviceId"`
	Seed     []byte `json:"seed"`
}

func identityPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "radio-px", "orbit-sim.json"), nil
}

// loadIdentity lê o id e a chave privada, criando os dois na primeira vez.
func loadIdentity(path string) (device [orbit.DeviceIDSize]byte, key ed25519.PrivateKey, err error) {
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return createIdentity(path)
	}
	if err != nil {
		return device, nil, err
	}
	var saved identity
	if err := json.Unmarshal(raw, &saved); err != nil {
		return device, nil, fmt.Errorf("%s: %w", path, err)
	}
	if len(saved.Seed) != ed25519.SeedSize {
		return device, nil, fmt.Errorf("%s: chave privada inválida", path)
	}
	if device, err = parseDeviceID(saved.DeviceID); err != nil {
		return device, nil, fmt.Errorf("%s: %w", path, err)
	}
	return device, ed25519.NewKeyFromSeed(saved.Seed), nil
}

func createIdentity(path string) (device [orbit.DeviceIDSize]byte, key ed25519.PrivateKey, err error) {
	if _, err = rand.Read(device[:]); err != nil {
		return device, nil, err
	}
	if _, key, err = ed25519.GenerateKey(rand.Reader); err != nil {
		return device, nil, err
	}
	raw, err := json.MarshalIndent(identity{DeviceID: hex.EncodeToString(device[:]), Seed: key.Seed()}, "", "  ")
	if err != nil {
		return device, nil, err
	}
	if err = os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return device, nil, err
	}
	return device, key, os.WriteFile(path, raw, 0o600)
}

func parseDeviceID(s string) (device [orbit.DeviceIDSize]byte, err error) {
	raw, err := hex.DecodeString(s)
	if err != nil || len(raw) != orbit.DeviceIDSize {
		return device, errors.New("o id precisa ter 16 dígitos hexadecimais")
	}
	copy(device[:], raw)
	return device, nil
}
