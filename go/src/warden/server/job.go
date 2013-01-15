package server

import (
	"bufio"
	"bytes"
	"io"
	"os/exec"

	"sync"
)

type Job struct {
	SpawnerBin string
	LinkerBin  string
	WorkDir    string

	Args  []string
	Env   []string
	Stdin io.Reader `json:"-"`

	// Tailers for stdout/stderr
	Stdout multiTailer `json:"-"`
	Stderr multiTailer `json:"-"`

	ExitStatus int

	// Mutex/condition variable for exit status
	em sync.Mutex
	ec sync.Cond
	eo sync.Once // Initializer
}

func (x *Job) runSpawner(ca chan bool, cb chan bool) {
	var err error

	defer close(ca)
	defer close(cb)

	y := exec.Command(x.SpawnerBin)
	y.Args = append(y.Args, x.WorkDir)
	y.Args = append(y.Args, x.Args...)
	y.Env = x.Env
	y.Stdin = x.Stdin

	stdout, err := y.StdoutPipe()
	if err != nil {
		panic(err)
	}

	_, err = y.StderrPipe()
	if err != nil {
		panic(err)
	}

	err = y.Start()
	if err != nil {
		panic(err)
	}

	b := bufio.NewReader(stdout)

	// Read the first line on stdout ("child_pid=12345")
	_, err = b.ReadString('\n')
	if err != nil {
		goto cleanup
	}

	ca <- true

	// Read the second line on stdout ("child active")
	_, err = b.ReadString('\n')
	if err != nil {
		goto cleanup
	}

	cb <- true

	// Don't care about exit status, the spawner did its job
	y.Wait()
	return

cleanup:
	// Clean up process
	y.Process.Kill()
	go y.Wait()
}

func (x *Job) Spawn() {
	//var err error
	var ok bool

	ca := make(chan bool, 1)
	cb := make(chan bool, 1)

	go x.runSpawner(ca, cb)

	// Wait for spawner to be ready
	_, ok = <-ca
	if !ok {
		panic("Error running spawner")
	}

	// Run linker just to make sure the child is run
	go x.Link()

	// Wait for spawner to run child
	_, ok = <-cb
	if !ok {
		panic("Error running spawner")
	}
}

type multiTailer struct {
	sync.Mutex
	b bytes.Buffer
	w []io.WriteCloser
	c bool
}

func (x *multiTailer) Add(w io.WriteCloser) {
	x.Lock()
	defer x.Unlock()

	b := x.b.Bytes()
	n, err := w.Write(b)
	if n == len(b) && err == nil {
		if x.c {
			w.Close()
		} else {
			x.w = append(x.w, w)
		}
	}
}

func (x *multiTailer) Write(b []byte) (int, error) {
	x.Lock()
	defer x.Unlock()

	// TODO: check if closed
	// return error if so

	n, err := x.b.Write(b)
	if n < len(b) || err != nil {
		return n, err
	}

	// Maintain list of writers where an error occurred
	var y []io.WriteCloser

	for _, w := range x.w {
		n, err := w.Write(b)
		if n < len(b) || err != nil {
			y = append(y, w)
		}
	}

	// Remove writers for which an error occurred
	if len(y) > 0 {
		var z []io.WriteCloser

		for _, w := range x.w {
			if w == y[0] {
				y = y[1:]
			} else {
				z = append(z, w)
			}
		}

		x.w = z
	}

	return len(b), nil
}

func (x *multiTailer) Close() {
	x.Lock()
	defer x.Unlock()

	for _, w := range x.w {
		w.Close()
	}

	x.c = true
	x.w = nil
}

func (x *multiTailer) CopyFrom(r io.Reader) (int64, error) {
	n, err := io.Copy(x, r)
	x.Close()
	return n, err
}

func (x *Job) runLinker() {
	var err error

	y := exec.Command(x.LinkerBin)
	y.Args = append(y.Args, x.WorkDir)

	stdout, err := y.StdoutPipe()
	if err != nil {
		panic(err)
	}

	stderr, err := y.StderrPipe()
	if err != nil {
		panic(err)
	}

	err = y.Start()
	if err != nil {
		panic(err)
	}

	go x.Stdout.CopyFrom(stdout)
	go x.Stderr.CopyFrom(stderr)

	// Exit status
	s := 255

	err = y.Wait()
	if err != nil {
		_, ok := err.(*exec.ExitError)
		if ok {
			s = 1
		}
	} else {
		// No error means everything is OK
		s = 0
	}

	x.em.Lock()
	x.ExitStatus = s
	x.ec.Signal()
	x.em.Unlock()
}

func (x *Job) Link() int {
	y := func() {
		// Initialize exit status
		x.ExitStatus = -1

		// Initialize condition variable
		x.ec = sync.Cond{L: &x.em}

		// Run linker
		x.runLinker()
	}

	x.eo.Do(y)

	x.em.Lock()
	defer x.em.Unlock()

	var s int

	// Wait for exit
	for {
		s = x.ExitStatus
		if s >= 0 {
			break
		}
		x.ec.Wait()
	}

	return s
}
