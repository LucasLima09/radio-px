// Package orbit modela os dispositivos Orbit: transmitem um sinal BLE assinado
// com id e localização. Não há cadastro: o primeiro sinal válido cria o Orbit.
package orbit

import (
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

var ErrInvalidName = errors.New("invalid orbit name")

const maxName = 64

type Orbit struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
	// Identifier é o id do dispositivo que vem no sinal assinado.
	Identifier string `json:"identifier"`
	// Active falso bloqueia o Orbit: seus sinais são recusados.
	Active    bool      `json:"active"`
	CreatedAt time.Time `json:"createdAt"`
	// Última posição recebida; nula se nenhum sinal chegou ainda.
	Last *LastSignal `json:"last,omitempty"`
}

type LastSignal struct {
	Latitude  float64   `json:"lat"`
	Longitude float64   `json:"lng"`
	At        time.Time `json:"at"`
}

// Discovered monta o Orbit visto pela primeira vez, com um nome provisório que
// o admin pode trocar no painel.
func Discovered(identifier string) *Orbit {
	return &Orbit{
		ID:         uuid.New(),
		Name:       "Orbit " + identifier,
		Identifier: identifier,
		Active:     true,
		CreatedAt:  time.Now().UTC(),
	}
}

func (o *Orbit) Rename(name string) error {
	name = strings.TrimSpace(name)
	if name == "" || utf8.RuneCountInString(name) > maxName {
		return ErrInvalidName
	}
	o.Name = name
	return nil
}
