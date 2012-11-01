package pool

import (
	"container/list"
	"fmt"
	"io/ioutil"
	"os"
	"sync"
)

// Don't use ports upwards of 65000
const MaxPort = 65000

type Port struct {
	sync.Mutex

	// Use this port as offset for the port pool
	StartPort uint

	// Pool this many ports
	Size uint

	// Actual pool
	pool *list.List
}

func (p *Port) init() {
	if p.pool == nil {
		p.pool = list.New()

		if p.StartPort == 0 {
			f, err := os.Open("/proc/sys/net/ipv4/ip_local_port_range")
			if err != nil {
				panic(err)
			}

			data, err := ioutil.ReadAll(f)
			if err != nil {
				panic(err)
			}

			var first, last uint16

			n, err := fmt.Sscan(string(data), &first, &last)
			if n != 2 {
				panic(err)
			}

			f.Close()

			p.StartPort = uint(last + 1)
		}

		if p.StartPort < 1024 {
			panic("Invalid StartPort")
		}

		if p.Size == 0 {
			p.Size = MaxPort - p.StartPort + 1
		}

		if p.StartPort+p.Size > (MaxPort + 1) {
			panic("Invalid Size")
		}

		for i := p.StartPort; i < (p.StartPort + p.Size); i++ {
			p.pool.PushBack(i)
		}
	}
}

func (p *Port) Acquire() *uint {
	p.Lock()
	defer p.Unlock()

	p.init()

	e := p.pool.Front()
	if e == nil {
		return nil
	}

	i := p.pool.Remove(e).(uint)

	return &i
}

func (p *Port) Release(i uint) {
	p.Lock()
	defer p.Unlock()

	p.init()

	p.pool.PushBack(i)
}

func (p *Port) Remove(i uint) bool {
	p.Lock()
	defer p.Unlock()

	p.init()

	for e := p.pool.Front(); e != nil; e = e.Next() {
		i_ := e.Value.(uint)
		if i == i_ {
			p.pool.Remove(e)
			return true
		}
	}

	return false
}
