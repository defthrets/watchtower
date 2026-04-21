// Package bus is the inter-process message bus abstraction.
//
// The concrete transport is NATS — see README "Architecture decisions".
// Binaries code against this interface so tests can swap in an in-memory
// implementation.
package bus

import "context"

type Handler func(subject string, data []byte)

type Bus interface {
	Publish(ctx context.Context, subject string, data []byte) error
	Subscribe(ctx context.Context, subject string, handler Handler) (Subscription, error)
	Close() error
}

type Subscription interface {
	Unsubscribe() error
}
