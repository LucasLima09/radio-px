package orbit

import (
	"strings"
	"testing"
)

func TestDiscoveredAndRename(t *testing.T) {
	o := Discovered("A1B2C3D401020304")
	if o.Name != "Orbit A1B2C3D401020304" || o.Identifier != "A1B2C3D401020304" || !o.Active {
		t.Fatalf("unexpected orbit: %+v", o)
	}
	if err := o.Rename("  Caminhão 12 "); err != nil || o.Name != "Caminhão 12" {
		t.Fatalf("Rename: %v, %q", err, o.Name)
	}
	for _, name := range []string{"", "   ", strings.Repeat("a", 65)} {
		if err := o.Rename(name); err != ErrInvalidName {
			t.Fatalf("Rename(%q) = %v", name, err)
		}
	}
}
