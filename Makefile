# Watchtower — build / install / run
#
# Targets:
#   build       compile all four binaries into ./bin/
#   install     install binaries + systemd units (needs sudo on Linux)
#   uninstall   reverse of install
#   run         run all four binaries in the foreground (dev)
#   clean       rm -rf ./bin/
#   fmt/vet/test/tidy   standard Go housekeeping

GO ?= go
BIN_DIR := bin
BINS := relay recorder detector api

VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
COMMIT  := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
BUILDTS := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
MODULE  := github.com/defthrets/watchtower

LDFLAGS := -s -w \
	-X '$(MODULE)/internal/version.Version=$(VERSION)' \
	-X '$(MODULE)/internal/version.Commit=$(COMMIT)' \
	-X '$(MODULE)/internal/version.BuildTime=$(BUILDTS)'

INSTALL_PREFIX ?= /usr/local
SYSTEMD_DIR    ?= /etc/systemd/system
STATE_DIR      ?= /var/lib/watchtower

.PHONY: all build clean fmt vet test tidy install uninstall run help

all: build

build: $(addprefix $(BIN_DIR)/watchtower-,$(BINS))

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

$(BIN_DIR)/watchtower-%: cmd/%/main.go | $(BIN_DIR)
	$(GO) build -ldflags "$(LDFLAGS)" -o $@ ./cmd/$*

clean:
	rm -rf $(BIN_DIR)

fmt:
	$(GO) fmt ./...

vet:
	$(GO) vet ./...

test:
	$(GO) test ./...

tidy:
	$(GO) mod tidy

install: build
	install -d $(DESTDIR)$(INSTALL_PREFIX)/bin
	install -d $(DESTDIR)$(STATE_DIR)/clips
	for b in $(BINS); do \
		install -m 0755 $(BIN_DIR)/watchtower-$$b $(DESTDIR)$(INSTALL_PREFIX)/bin/; \
	done
	install -d $(DESTDIR)$(SYSTEMD_DIR)
	for b in $(BINS); do \
		install -m 0644 deploy/systemd/watchtower-$$b.service $(DESTDIR)$(SYSTEMD_DIR)/; \
	done
	@if [ -z "$(DESTDIR)" ]; then systemctl daemon-reload; fi
	@echo
	@echo "Installed. Next steps:"
	@echo "  1. Ensure nats-server is running (see README)."
	@echo "  2. cp docs/config.example.yaml ~/.watchtower/config.yaml and edit."
	@echo "  3. Edit /etc/systemd/system/watchtower-*.service — set User/Group."
	@echo "  4. systemctl enable --now watchtower-relay watchtower-recorder watchtower-detector watchtower-api"

uninstall:
	-systemctl disable --now $(addprefix watchtower-,$(BINS)) 2>/dev/null || true
	rm -f $(addprefix $(SYSTEMD_DIR)/watchtower-,$(addsuffix .service,$(BINS)))
	rm -f $(addprefix $(INSTALL_PREFIX)/bin/watchtower-,$(BINS))
	systemctl daemon-reload 2>/dev/null || true

# Dev mode — runs all four in the foreground. Ctrl-C kills all.
run: build
	@echo "Dev run — Ctrl-C to stop all four."
	@trap 'kill 0' INT TERM EXIT; \
	$(BIN_DIR)/watchtower-relay    --config $$HOME/.watchtower/config.yaml & \
	$(BIN_DIR)/watchtower-recorder --config $$HOME/.watchtower/config.yaml & \
	$(BIN_DIR)/watchtower-detector --config $$HOME/.watchtower/config.yaml & \
	$(BIN_DIR)/watchtower-api      --config $$HOME/.watchtower/config.yaml & \
	wait

help:
	@echo "Watchtower make targets:"
	@echo "  build      Compile all four binaries to ./bin/"
	@echo "  install    Install binaries + systemd units (sudo)"
	@echo "  uninstall  Remove binaries + systemd units (sudo)"
	@echo "  run        Run all four in foreground (dev)"
	@echo "  clean      Remove ./bin/"
	@echo "  fmt vet test tidy   Standard Go targets"
