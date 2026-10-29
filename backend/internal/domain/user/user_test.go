package user

import "testing"

func TestValidUsername(t *testing.T) {
	for _, ok := range []string{"lucas", "lucas.lima", "Lucas_09", "a-b"} {
		if !ValidUsername(ok) {
			t.Fatalf("ValidUsername(%q) rejected", ok)
		}
	}
	for _, bad := range []string{"ab", "lucas lima", "lúcas", "lucas@", "abcdefghijklmnopqrstuvwxyz12345"} {
		if ValidUsername(bad) {
			t.Fatalf("ValidUsername(%q) accepted", bad)
		}
	}
}

func TestNormalizeLastName(t *testing.T) {
	for in, want := range map[string]string{" Lima ": "Lima", "D'Ávila Souza-Neto": "D'Ávila Souza-Neto", "": ""} {
		if got, err := NormalizeLastName(in); err != nil || got != want {
			t.Fatalf("NormalizeLastName(%q) = %q, %v", in, got, err)
		}
	}
	for _, in := range []string{"Lima2", "--", "Lima  Souza"} {
		if _, err := NormalizeLastName(in); err != ErrInvalidLastName {
			t.Fatalf("NormalizeLastName(%q) accepted", in)
		}
	}
}

func TestNormalizePlate(t *testing.T) {
	for in, want := range map[string]string{
		"ABC1D23":    "ABC1D23",
		" abc 1d23 ": "ABC1D23",
		"abc-1234":   "ABC1C34",
		"XYZ9087":    "XYZ9A87",
		"":           "",
	} {
		if got, err := NormalizePlate(in); err != nil || got != want {
			t.Fatalf("NormalizePlate(%q) = %q, %v", in, got, err)
		}
	}
	for _, in := range []string{"AB1234", "ABCD123", "1BC1234", "ABC1D234", "ABC1DD3"} {
		if _, err := NormalizePlate(in); err != ErrInvalidPlate {
			t.Fatalf("NormalizePlate(%q) accepted", in)
		}
	}
}

func TestNormalizePhone(t *testing.T) {
	for in, want := range map[string]string{"(11) 98765-4321": "11987654321", "1133334444": "1133334444", "  ": ""} {
		if got, err := NormalizePhone(in); err != nil || got != want {
			t.Fatalf("NormalizePhone(%q) = %q, %v", in, got, err)
		}
	}
	for _, in := range []string{"1234", "abc", "119876543210", "0133334444", "11387654321"} {
		if _, err := NormalizePhone(in); err != ErrInvalidPhone {
			t.Fatalf("NormalizePhone(%q) accepted", in)
		}
	}
}
