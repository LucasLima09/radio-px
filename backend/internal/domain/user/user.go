package user

import (
	"errors"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

var (
	ErrInvalidUsername  = errors.New("username must have 3 to 30 characters: letters, numbers, dot, dash or underscore")
	ErrWeakPassword     = errors.New("password must have at least 6 characters")
	ErrUsernameTaken    = errors.New("username already taken")
	ErrInvalidRole      = errors.New("invalid role")
	ErrInvalidFirstName = errors.New("first name must have only letters and at most 50 characters")
	ErrInvalidLastName  = errors.New("last name must have only letters and at most 50 characters")
	ErrInvalidPlate     = errors.New("invalid vehicle plate")
	ErrInvalidPhone     = errors.New("invalid phone")
)

// Roles. Todos os usuários nascem como user; admin é promovido manualmente no
// banco e refletido no token de acesso.
const (
	RoleUser  = "user"
	RoleAdmin = "admin"
)

type User struct {
	ID           uuid.UUID
	Username     string
	FirstName    string
	LastName     string
	VehiclePlate string
	Phone        string
	Avatar       string
	PasswordHash string
	Role         string
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

func New(username, passwordHash string) (*User, error) {
	username = strings.TrimSpace(username)

	if !ValidUsername(username) {
		return nil, ErrInvalidUsername
	}
	if len(passwordHash) == 0 {
		return nil, ErrWeakPassword
	}

	now := time.Now().UTC()
	return &User{
		ID:           uuid.New(),
		Username:     username,
		PasswordHash: passwordHash,
		Role:         RoleUser,
		CreatedAt:    now,
		UpdatedAt:    now,
	}, nil
}

type Public struct {
	ID           uuid.UUID `json:"id"`
	Username     string    `json:"username"`
	FirstName    string    `json:"firstName,omitempty"`
	LastName     string    `json:"lastName,omitempty"`
	VehiclePlate string    `json:"vehiclePlate,omitempty"`
	Phone        string    `json:"phone,omitempty"`
	Avatar       string    `json:"avatar,omitempty"`
	Role         string    `json:"role"`
	CreatedAt    time.Time `json:"createdAt"`
}

func (u *User) Public() Public {
	return Public{
		ID:           u.ID,
		Username:     u.Username,
		FirstName:    u.FirstName,
		LastName:     u.LastName,
		VehiclePlate: u.VehiclePlate,
		Phone:        u.Phone,
		Avatar:       u.Avatar,
		Role:         u.Role,
		CreatedAt:    u.CreatedAt,
	}
}

// Nome de usuário usado no login: sem espaços, só letras, números, ponto,
// hífen e sublinhado.
var usernameRe = regexp.MustCompile(`^[A-Za-z0-9._-]{3,30}$`)

// ValidUsername reporta se username pode ser usado para entrar na conta.
func ValidUsername(username string) bool {
	return usernameRe.MatchString(username)
}

// Letras, com espaço, apóstrofo ou hífen entre as partes (D'Ávila Souza-Neto).
var nameRe = regexp.MustCompile(`^\pL+(?:[ '\-]\pL+)*$`)

// NormalizeFirstName apara o primeiro nome; vazio é aceito.
func NormalizeFirstName(value string) (string, error) {
	return normalizeName(value, ErrInvalidFirstName)
}

// NormalizeLastName apara o sobrenome; vazio é aceito.
func NormalizeLastName(value string) (string, error) {
	return normalizeName(value, ErrInvalidLastName)
}

func normalizeName(value string, invalid error) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", nil
	}
	if utf8.RuneCountInString(value) > 50 || !nameRe.MatchString(value) {
		return "", invalid
	}
	return value, nil
}

var (
	mercosulRe  = regexp.MustCompile(`^[A-Z]{3}[0-9][A-Z][0-9]{2}$`)
	oldPlateRe  = regexp.MustCompile(`^[A-Z]{3}[0-9]{4}$`)
	nonAlnumRe  = regexp.MustCompile(`[^A-Z0-9]`)
	nonDigitsRe = regexp.MustCompile(`[^0-9]`)
)

// NormalizePlate devolve a placa no padrão Mercosul (ABC1D23). Uma placa
// antiga (ABC1234) é convertida pela regra oficial: o quinto caractere vira
// letra (0→A ... 9→J). Vazio é aceito e limpa o campo.
func NormalizePlate(value string) (string, error) {
	value = nonAlnumRe.ReplaceAllString(strings.ToUpper(value), "")
	if value == "" {
		return "", nil
	}
	if oldPlateRe.MatchString(value) {
		value = value[:4] + string(rune('A'+value[4]-'0')) + value[5:]
	}
	if !mercosulRe.MatchString(value) {
		return "", ErrInvalidPlate
	}
	return value, nil
}

// NormalizePhone guarda só os dígitos de um telefone com DDD: fixo (10
// dígitos) ou celular (11 dígitos, começando com 9). Vazio é aceito e limpa
// o campo.
func NormalizePhone(value string) (string, error) {
	if strings.TrimSpace(value) == "" {
		return "", nil
	}
	digits := nonDigitsRe.ReplaceAllString(value, "")
	if len(digits) < 10 || len(digits) > 11 || digits[0] == '0' {
		return "", ErrInvalidPhone
	}
	if len(digits) == 11 && digits[2] != '9' {
		return "", ErrInvalidPhone
	}
	return digits, nil
}

// ValidRole reporta se role é uma das roles aceitas.
func ValidRole(role string) bool {
	return role == RoleUser || role == RoleAdmin
}
