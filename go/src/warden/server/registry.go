package server

import (
	"errors"
	"sync"
)

var (
	ErrAlreadyRegistered = errors.New("container is already registered")
	ErrNotRegistered     = errors.New("container is not registered")
)

type Registry struct {
	sync.Mutex

	C map[string]Container
}

func NewRegistry() *Registry {
	r := &Registry{
		C: make(map[string]Container),
	}

	return r
}

func (x *Registry) Register(c Container) error {
	x.Lock()
	defer x.Unlock()

	h := c.Handle()

	_, ok := x.C[h]
	if ok {
		return ErrAlreadyRegistered
	}

	x.C[h] = c

	return nil
}

func (x *Registry) Unregister(c Container) error {
	x.Lock()
	defer x.Unlock()

	h := c.Handle()

	_, ok := x.C[h]
	if !ok {
		return ErrNotRegistered
	}

	delete(x.C, h)

	return nil
}

func (x *Registry) Find(h string) Container {
	x.Lock()
	defer x.Unlock()

	y, ok := x.C[h]
	if !ok {
		return nil
	}

	return y
}
