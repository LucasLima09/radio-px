package location

import (
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/lucas/radio-px-backend/internal/domain/orbit"
)

var (
	ErrInvalidCoord = errors.New("invalid coordinates")
	ErrInvalidRSSI  = errors.New("invalid rssi")
	ErrInvalidTime  = errors.New("invalid encounter time")
)

// O app guarda os encontros feitos sem internet e envia depois, com a hora
// real do encontro. Aceita até essa idade; o limite no futuro tolera relógio
// do aparelho um pouco adiantado.
const (
	MaxEncounterAge = 30 * 24 * time.Hour
	MaxClockSkew    = 5 * time.Minute
	// MaxSignalAge é quanto a hora do sinal pode diferir da hora em que o app
	// o ouviu. O app usa o mesmo limite.
	MaxSignalAge = 2 * time.Minute
)

type Location struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	ChannelID *uuid.UUID
	Latitude  float64
	Longitude float64
	// Orbit cujo sinal assinado trouxe a posição. Nulo
	// nas posições antigas do GPS contínuo e nas recebidas pelo WebSocket da
	// sala. OrbitName é uma cópia do nome no momento do encontro, para o
	// histórico sobreviver se o Orbit for renomeado ou apagado.
	OrbitID   *uuid.UUID
	OrbitName *string
	RSSI      *int
	CreatedAt time.Time
}

// channelID é nil quando a posição é reportada fora de um canal (beacon
// sempre ativo em segundo plano).
func New(userID uuid.UUID, channelID *uuid.UUID, latitude, longitude float64) (*Location, error) {
	if err := validateCoords(latitude, longitude); err != nil {
		return nil, err
	}

	return &Location{
		ID:        uuid.New(),
		UserID:    userID,
		ChannelID: channelID,
		Latitude:  latitude,
		Longitude: longitude,
		CreatedAt: time.Now().UTC(),
	}, nil
}

// NewEncounter registra o sinal de um Orbit recebido pelo app. Posição e hora
// vêm do sinal assinado, não do aparelho do motorista. receivedAt é quando o
// app ouviu o sinal (pode ser antigo, se ficou na fila sem internet); zero
// significa agora. rssi é opcional: nem todo navegador expõe a intensidade.
func NewEncounter(userID uuid.UUID, s orbit.Signal, o *orbit.Orbit, rssi *int, receivedAt time.Time) (*Location, error) {
	if err := ValidateEncounter(s, rssi, receivedAt); err != nil {
		return nil, err
	}
	orbitID := o.ID
	orbitName := o.Name
	return &Location{
		ID:        uuid.New(),
		UserID:    userID,
		Latitude:  s.Latitude,
		Longitude: s.Longitude,
		OrbitID:   &orbitID,
		OrbitName: &orbitName,
		RSSI:      rssi,
		CreatedAt: s.At.UTC(),
	}, nil
}

// ValidateEncounter confere o sinal antes de o Orbit ser criado no banco.
func ValidateEncounter(s orbit.Signal, rssi *int, receivedAt time.Time) error {
	if err := validateCoords(s.Latitude, s.Longitude); err != nil {
		return err
	}
	if rssi != nil && (*rssi < -127 || *rssi > 20) {
		return ErrInvalidRSSI
	}
	now := time.Now().UTC()
	if receivedAt.IsZero() {
		receivedAt = now
	}
	if s.At.After(now.Add(MaxClockSkew)) || s.At.Before(now.Add(-MaxEncounterAge)) {
		return ErrInvalidTime
	}
	// Um sinal gravado e retransmitido depois chega com a hora velha.
	if receivedAt.Sub(s.At).Abs() > MaxSignalAge {
		return ErrInvalidTime
	}
	return nil
}

func validateCoords(latitude, longitude float64) error {
	if latitude < -90 || latitude > 90 {
		return ErrInvalidCoord
	}
	if longitude < -180 || longitude > 180 {
		return ErrInvalidCoord
	}
	return nil
}

// Report é a última posição conhecida de um usuário, agregada para o painel do
// admin.
type Report struct {
	UserID     uuid.UUID
	Username   string
	Latitude   float64
	Longitude  float64
	OrbitName  *string
	RSSI       *int
	ReportedAt time.Time
}
