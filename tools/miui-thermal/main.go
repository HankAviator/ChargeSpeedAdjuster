package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

var thermalKey = []byte("thermalopenssl.h")

func main() {
	decrypt := flag.Bool("d", false, "decrypt input files instead of encrypting them")
	input := flag.String("i", "", "input directory")
	output := flag.String("o", "", "output directory")
	flag.Parse()

	if *input == "" || *output == "" {
		fmt.Fprintln(os.Stderr, "both -i and -o are required")
		os.Exit(2)
	}

	if err := run(*decrypt, *input, *output); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(decrypt bool, inputDir, outputDir string) error {
	entries, err := os.ReadDir(inputDir)
	if err != nil {
		return fmt.Errorf("read input directory: %w", err)
	}
	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		return fmt.Errorf("create output directory: %w", err)
	}

	processed := 0
	for _, entry := range entries {
		if !entry.Type().IsRegular() || !strings.HasSuffix(entry.Name(), ".conf") {
			continue
		}

		inputPath := filepath.Join(inputDir, entry.Name())
		outputPath := filepath.Join(outputDir, entry.Name())
		data, err := os.ReadFile(inputPath)
		if err != nil {
			return fmt.Errorf("read %s: %w", inputPath, err)
		}

		var result []byte
		if decrypt {
			result, err = decryptThermal(data)
		} else {
			result, err = encryptThermal(data)
		}
		if err != nil {
			return fmt.Errorf("process %s: %w", inputPath, err)
		}

		if err := writeAtomic(outputPath, result, 0o644); err != nil {
			return fmt.Errorf("write %s: %w", outputPath, err)
		}
		processed++
	}

	if processed == 0 {
		return errors.New("no .conf files were processed")
	}
	return nil
}

func encryptThermal(plain []byte) ([]byte, error) {
	block, err := aes.NewCipher(thermalKey)
	if err != nil {
		return nil, err
	}
	padded := pkcs7Pad(plain, block.BlockSize())
	out := make([]byte, len(padded))
	cipher.NewCBCEncrypter(block, thermalKey).CryptBlocks(out, padded)
	return out, nil
}

func decryptThermal(encrypted []byte) ([]byte, error) {
	block, err := aes.NewCipher(thermalKey)
	if err != nil {
		return nil, err
	}
	if len(encrypted) == 0 || len(encrypted)%block.BlockSize() != 0 {
		return nil, errors.New("ciphertext is not a non-empty sequence of AES blocks")
	}

	out := make([]byte, len(encrypted))
	cipher.NewCBCDecrypter(block, thermalKey).CryptBlocks(out, encrypted)
	return pkcs7Unpad(out, block.BlockSize())
}

func pkcs7Pad(input []byte, blockSize int) []byte {
	padding := blockSize - len(input)%blockSize
	return append(input, bytes.Repeat([]byte{byte(padding)}, padding)...)
}

func pkcs7Unpad(input []byte, blockSize int) ([]byte, error) {
	if len(input) == 0 || len(input)%blockSize != 0 {
		return nil, errors.New("invalid padded plaintext length")
	}
	padding := int(input[len(input)-1])
	if padding == 0 || padding > blockSize || padding > len(input) {
		return nil, errors.New("invalid PKCS#7 padding length")
	}
	for _, value := range input[len(input)-padding:] {
		if int(value) != padding {
			return nil, errors.New("invalid PKCS#7 padding bytes")
		}
	}
	return input[:len(input)-padding], nil
}

func writeAtomic(path string, data []byte, mode os.FileMode) error {
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, data, mode); err != nil {
		return err
	}
	if err := os.Chmod(temporary, mode); err != nil {
		_ = os.Remove(temporary)
		return err
	}
	if err := os.Rename(temporary, path); err != nil {
		_ = os.Remove(temporary)
		return err
	}
	return nil
}
