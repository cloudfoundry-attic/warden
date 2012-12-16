package pool

type UserId uint16

func (x UserId) Next() Poolable {
	return UserId(x + 1)
}

func (x UserId) Equals(y Poolable) bool {
	z, ok := y.(UserId)
	return ok && x == z
}

type UserPool struct {
	*Pool
}

func NewUserPool(start int, size int) *UserPool {
	p := &UserPool{}
	p.Pool = NewPool(UserId(start), size)
	return p
}

func (p *UserPool) Acquire() (x UserId, ok bool) {
	y, ok := p.Pool.Acquire()
	if ok {
		x = y.(UserId)
	}

	return
}

func (p *UserPool) Release(x UserId) {
	p.Pool.Release(x)
}

func (p *UserPool) Remove(x UserId) bool {
	return p.Pool.Remove(x)
}
