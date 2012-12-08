package pool

import (
	"container/list"
	"sync"
)

type Poolable interface {
	Next() Poolable
	Equals(Poolable) bool
}

type Pool struct {
	sync.Mutex
	list *list.List
}

func NewPool(x Poolable, size int) *Pool {
	p := &Pool{}
	p.list = list.New()

	// Fill the pool
	for ; size > 0; size-- {
		p.list.PushBack(x)
		x = x.Next()
	}

	return p
}

func (p *Pool) Acquire() (x Poolable, ok bool) {
	p.Lock()
	defer p.Unlock()

	e := p.list.Front()
	if e == nil {
		return
	}

	x = p.list.Remove(e).(Poolable)
	return x, true
}

func (p *Pool) Release(x Poolable) {
	p.Lock()
	defer p.Unlock()

	p.list.PushBack(x)
}

func (p *Pool) Remove(x Poolable) bool {
	p.Lock()
	defer p.Unlock()

	for e := p.list.Front(); e != nil; e = e.Next() {
		y := e.Value.(Poolable)
		if x.Equals(y) {
			p.list.Remove(e)
			return true
		}
	}

	return false
}
