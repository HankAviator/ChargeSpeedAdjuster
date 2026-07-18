package main

import (
	"bytes"
	"testing"
)

func TestRoundTrip(t *testing.T) {
	original := []byte("[NORMAL-SIC-BAT]\ntrig\t35000\nclr\t34000\n")
	encrypted, err := encryptThermal(original)
	if err != nil {
		t.Fatal(err)
	}
	decrypted, err := decryptThermal(encrypted)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(original, decrypted) {
		t.Fatalf("round trip mismatch: %q", decrypted)
	}
}

func TestRejectsCorruptPadding(t *testing.T) {
	encrypted, err := encryptThermal([]byte("thermal"))
	if err != nil {
		t.Fatal(err)
	}
	encrypted[len(encrypted)-1] ^= 0xff
	if _, err := decryptThermal(encrypted); err == nil {
		t.Fatal("corrupt padding was accepted")
	}
}
