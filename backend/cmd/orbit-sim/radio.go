package main

import (
	"fmt"

	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/prop"
	"github.com/lucas/radio-px-backend/internal/domain/orbit"
)

const (
	bluezService   = "org.bluez"
	adIface        = "org.bluez.LEAdvertisement1"
	adManagerIface = "org.bluez.LEAdvertisingManager1"
)

// radio transmite anúncios BLE pelo BlueZ, via D-Bus. Não precisa de root.
type radio struct {
	conn    *dbus.Conn
	adapter dbus.BusObject
	onAir   []dbus.ObjectPath
	next    int
}

func openRadio(adapter string) (*radio, error) {
	conn, err := dbus.ConnectSystemBus()
	if err != nil {
		return nil, fmt.Errorf("D-Bus do sistema: %w", err)
	}
	r := &radio{conn: conn, adapter: conn.Object(bluezService, dbus.ObjectPath("/org/bluez/"+adapter))}
	powered, err := r.adapter.GetProperty("org.bluez.Adapter1.Powered")
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("adaptador %s: %w", adapter, err)
	}
	if on, _ := powered.Value().(bool); !on {
		conn.Close()
		return nil, fmt.Errorf("o Bluetooth (%s) está desligado", adapter)
	}
	if _, err := r.adapter.GetProperty(adManagerIface + ".SupportedInstances"); err != nil {
		conn.Close()
		return nil, fmt.Errorf("o adaptador %s não transmite anúncios BLE: %w", adapter, err)
	}
	return r, nil
}

// Transmit põe os anúncios no ar e só depois tira os anteriores, para não
// haver intervalo em silêncio na troca de sinal.
func (r *radio) Transmit(fragments [][]byte) error {
	previous := r.onAir
	r.onAir = nil
	for _, data := range fragments {
		if err := r.register(data); err != nil {
			r.onAir = append(r.onAir, previous...)
			return fmt.Errorf("transmitindo anúncio: %w", err)
		}
	}
	return r.unregister(previous)
}

func (r *radio) register(data []byte) error {
	path := dbus.ObjectPath(fmt.Sprintf("/com/radiopx/orbit/ad%d", r.next))
	r.next++
	if err := r.conn.Export(advertisement{}, path, adIface); err != nil {
		return err
	}
	// "broadcast": não conectável e sem flags, deixa os 31 bytes livres.
	_, err := prop.Export(r.conn, path, prop.Map{adIface: {
		"Type": {Value: "broadcast"},
		"ManufacturerData": {Value: map[uint16]dbus.Variant{
			orbit.CompanyID: dbus.MakeVariant(data),
		}},
	}})
	if err != nil {
		return err
	}
	call := r.adapter.Call(adManagerIface+".RegisterAdvertisement", 0, path, map[string]dbus.Variant{})
	if call.Err != nil {
		return call.Err
	}
	r.onAir = append(r.onAir, path)
	return nil
}

func (r *radio) unregister(paths []dbus.ObjectPath) error {
	var first error
	for _, path := range paths {
		call := r.adapter.Call(adManagerIface+".UnregisterAdvertisement", 0, path)
		if call.Err != nil && first == nil {
			first = call.Err
		}
		_ = r.conn.Export(nil, path, adIface)
		_ = r.conn.Export(nil, path, "org.freedesktop.DBus.Properties")
	}
	return first
}

func (r *radio) Close() {
	_ = r.unregister(r.onAir)
	r.conn.Close()
}

type advertisement struct{}

// Release é chamado pelo BlueZ quando ele mesmo encerra o anúncio.
func (advertisement) Release() *dbus.Error { return nil }
