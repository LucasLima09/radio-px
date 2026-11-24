package orbit

import "testing"

func TestNew(t *testing.T) {
	o, err := New("  Orbit do Lucas ", " ORBIT-LUCAS ")
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if o.Name != "Orbit do Lucas" || o.Identifier != "ORBIT-LUCAS" || !o.Active {
		t.Fatalf("unexpected orbit: %+v", o)
	}
}

func TestNewRejects(t *testing.T) {
	long := "0123456789012345678901234567890123456789012345678901234567890123456789"
	cases := []struct {
		name, identifier string
		want             error
	}{
		{"", "ORBIT", ErrInvalidName},
		{long, "ORBIT", ErrInvalidName},
		{"Orbit", "  ", ErrInvalidIdentifier},
		{"Orbit", long, ErrInvalidIdentifier},
		{"Orbit", "ORB\nIT", ErrInvalidIdentifier},
	}
	for _, c := range cases {
		if _, err := New(c.name, c.identifier); err != c.want {
			t.Fatalf("New(%q, %q) = %v, want %v", c.name, c.identifier, err, c.want)
		}
	}
}
