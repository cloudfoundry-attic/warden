package pool

import (
	"container/list"
	"fmt"
	"sync"
)

type Poolable interface {
	fmt.Stringer

	Next() Poolable
	Equals(Poolable) bool
}

type Pool struct {
	sync.Mutex

	m map[string]bool // Original
	a map[string]bool // Available
	l *list.List
}

func NewPool(x Poolable, size int) *Pool {
	p := &Pool{}
	p.m = make(map[string]bool)
	p.a = make(map[string]bool)
	p.l = list.New()

	// Fill the pool
	for ; size > 0; size-- {
		p.m[x.String()] = true
		p.a[x.String()] = true
		p.l.PushBack(x)
		x = x.Next()
	}

	return p
}

func (p *Pool) Acquire() (x Poolable, ok bool) {
	p.Lock()
	defer p.Unlock()

	e := p.l.Front()
	if e == nil {
		return
	}

	x = p.l.Remove(e).(Poolable)
	delete(p.a, x.String())
	return x, true
}

func (p *Pool) Release(x Poolable) {
	p.Lock()
	defer p.Unlock()

	p.l.PushBack(x)
	p.a[x.String()] = true
}

func (p *Pool) Remove(x Poolable) bool {
	p.Lock()
	defer p.Unlock()

	for e := p.l.Front(); e != nil; e = e.Next() {
		y := e.Value.(Poolable)
		if x.Equals(y) {
			p.l.Remove(e)
			delete(p.a, x.String())
			return true
		}
	}

	return false
}
