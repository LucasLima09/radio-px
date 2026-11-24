// Package orbit modela os dispositivos Orbit: cadastrados uma vez no painel e
// reconhecidos pelos apps via Bluetooth pelo nome que anunciam.
package orbit

import (
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

var (
	ErrInvalidName       = errors.New("invalid orbit name")
	ErrInvalidIdentifier = errors.New("invalid orbit identifier")
)

const maxField = 64

type Orbit struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
	// Identifier é o nome que o dispositivo anuncia no Bluetooth (local name).
	// É por ele que o app reconhece o Orbit, então precisa ser exato.
	Identifier string    `json:"identifier"`
	Active     bool      `json:"active"`
	CreatedAt  time.Time `json:"createdAt"`
}

func New(name, identifier string) (*Orbit, error) {
	o := &Orbit{ID: uuid.New(), Active: true, CreatedAt: time.Now().UTC()}
	if err := o.Rename(name, identifier); err != nil {
		return nil, err
	}
	return o, nil
}

// Rename troca nome e identificador, validando os dois.
func (o *Orbit) Rename(name, identifier string) error {
	name = strings.TrimSpace(name)
	identifier = strings.TrimSpace(identifier)
	if name == "" || utf8.RuneCountInString(name) > maxField {
		return ErrInvalidName
	}
	// O nome anunciado no BLE é curto (até ~29 bytes no anúncio) e não tem
	// quebras de linha; 64 dá folga para o nome completo do GAP.
	if identifier == "" || len(identifier) > maxField || strings.ContainsAny(identifier, "\r\n\t") {
		return ErrInvalidIdentifier
	}
	o.Name = name
	o.Identifier = identifier
	return nil
}
