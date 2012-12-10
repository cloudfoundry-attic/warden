package pool

type user struct {
	u uint16
}

func (x user) Next() Poolable {
	return user{x.u + 1}
}

func (x user) Equals(y Poolable) bool {
	z, ok := y.(user)
	return ok && x.u == z.u
}

type UserPool struct {
	*Pool
}

func NewUserPool(start int, size int) *UserPool {
	p := &UserPool{}
	p.Pool = NewPool(user{uint16(start)}, size)
	return p
}

func (p *UserPool) Acquire() (x uint16, ok bool) {
	y, ok := p.Pool.Acquire()
	if ok {
		x = y.(user).u
	}

	return
}

func (p *UserPool) Release(x uint16) {
	p.Pool.Release(user{x})
}

func (p *UserPool) Remove(x uint16) bool {
	return p.Pool.Remove(user{x})
}
