// Package config loads watchtower configuration from YAML.
//
// Full schema lives at docs/config.example.yaml. This file is a
// scaffold stub; real parsing lands with the relay implementation.
package config

type Config struct {
	Path string
}

func Load(path string) (*Config, error) {
	return &Config{Path: path}, nil
}
