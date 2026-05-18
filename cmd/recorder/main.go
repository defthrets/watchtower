package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/defthrets/watchtower/internal/config"
	"github.com/defthrets/watchtower/internal/version"
)

const role = "recorder"

func main() {
	var (
		configPath = flag.String("config", os.Getenv("WATCHTOWER_CONFIG"), "path to config.yaml")
		showVer    = flag.Bool("version", false, "print version and exit")
	)
	flag.Parse()

	if *showVer {
		fmt.Println(version.String())
		return
	}

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	logger = logger.With("role", role)
	slog.SetDefault(logger)

	logger.Info("starting", "version", version.Version, "config", *configPath)

	if _, err := config.Load(*configPath); err != nil {
		logger.Error("config load failed", "err", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	logger.Info("scaffold no-op — recorder implementation lands after relay")
	<-ctx.Done()
	logger.Info("shutdown complete")
}
