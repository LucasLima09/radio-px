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
)

type Location struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	ChannelID *uuid.UUID
	Latitude  float64
	Longitude float64
	// Orbit cadastrado encontrado via Bluetooth que disparou o report. Nulo
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

// NewEncounter registra a posição do aparelho no momento em que ele encontrou
// um Orbit cadastrado via Bluetooth. rssi é opcional: nem todo navegador
// expõe a intensidade do sinal. at é a hora do encontro informada pelo app
// (pode ser antiga, se ficou na fila sem internet); zero significa agora.
func NewEncounter(userID uuid.UUID, latitude, longitude float64, o *orbit.Orbit, rssi *int, at time.Time) (*Location, error) {
	if err := validateCoords(latitude, longitude); err != nil {
		return nil, err
	}
	if rssi != nil && (*rssi < -127 || *rssi > 20) {
		return nil, ErrInvalidRSSI
	}
	now := time.Now().UTC()
	if at.IsZero() {
		at = now
	}
	if at.After(now.Add(MaxClockSkew)) || at.Before(now.Add(-MaxEncounterAge)) {
		return nil, ErrInvalidTime
	}

	orbitID := o.ID
	orbitName := o.Name
	return &Location{
		ID:        uuid.New(),
		UserID:    userID,
		Latitude:  latitude,
		Longitude: longitude,
		OrbitID:   &orbitID,
		OrbitName: &orbitName,
		RSSI:      rssi,
		CreatedAt: at.UTC(),
	}, nil
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
