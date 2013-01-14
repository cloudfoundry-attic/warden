package server

import (
	"io"
	"io/ioutil"
	. "launchpad.net/gocheck"
	"os"
	"path"
	"strings"
)

const spawnScript = `#!/usr/bin/env bash

WORK=$1

mkdir -p $WORK

shift

cat - > $WORK/stdin

# Acquire status lock
exec 3> $WORK/status.lock
flock -x 3

mkdir -p $WORK/fifo
mkfifo $WORK/fifo/kickstart
mkfifo $WORK/fifo/active

(
  # Setup fds
  exec < $WORK/stdin
  exec 1> $WORK/stdout
  exec 2> $WORK/stderr

  read _ < $WORK/fifo/kickstart
  rm $WORK/fifo/kickstart

  echo > $WORK/fifo/active
  rm $WORK/fifo/active

  # Run process
  exec $@
) &

child_pid=$!
echo child_pid=$child_pid

read _ < $WORK/fifo/active

echo child active

wait

echo $? > $WORK/status
`

const linkScript = `#!/usr/bin/env bash

WORK=$1

tail -n0 -s0.01 -f $WORK/stdout >&1 &
pidout=$!

tail -n0 -s0.01 -f $WORK/stderr >&2 &
piderr=$!

if [ -p $WORK/fifo/kickstart ]
then
  echo > $WORK/fifo/kickstart
fi

# Acquire status lock
exec 3> $WORK/status.lock
flock -x 3

# Give the tail processes some time
sleep 0.02

kill $pidout
kill $piderr
exit $(cat $WORK/status)
`

type JobSuite struct {
	tempDir string
	*Job
}

var _ = Suite(&JobSuite{})

func writeScript(name string, contents string) {
	var f *os.File
	var err error

	f, err = os.Create(name)
	if err != nil {
		panic(err)
	}

	_, err = f.Write([]byte(contents))
	if err != nil {
		panic(err)
	}

	err = f.Chmod(0755)
	if err != nil {
		panic(err)
	}

	err = f.Close()
	if err != nil {
		panic(err)
	}
}

func (s *JobSuite) SetUpTest(c *C) {
	var err error

	s.tempDir, err = ioutil.TempDir("", "JobSuite")
	if err != nil {
		panic(err)
	}

	spawnPath := path.Join(s.tempDir, "spawn.sh")
	writeScript(spawnPath, spawnScript)

	linkPath := path.Join(s.tempDir, "link.sh")
	writeScript(linkPath, linkScript)

	s.Job = &Job{
		SpawnerBin: spawnPath,
		LinkerBin:  linkPath,
		WorkDir:    s.tempDir,
	}
}

func (s *JobSuite) LinkAndCollect(c *C) (string, string, int) {
	cstdout := make(chan []byte)
	cstderr := make(chan []byte)
	cstatus := make(chan int)

	rout, wout := io.Pipe()
	rerr, werr := io.Pipe()

	// Stdout
	go func() {
		b, err := ioutil.ReadAll(rout)
		if err != nil {
			panic(err)
		}

		cstdout <- b
	}()

	// Stderr
	go func() {
		b, err := ioutil.ReadAll(rerr)
		if err != nil {
			panic(err)
		}

		cstderr <- b
	}()

	// Exit status
	go func() {
		cstatus <- s.Link()
	}()

	s.Stdout.Add(wout)
	s.Stderr.Add(werr)

	stdout := <-cstdout
	stderr := <-cstderr
	status := <-cstatus

	return string(stdout), string(stderr), status
}

func (s *JobSuite) TestSpawnWithArgs(c *C) {
	s.Job.Args = []string{"echo", "hello", "world"}
	s.Spawn()

	o, e, x := s.LinkAndCollect(c)
	c.Check(o, DeepEquals, "hello world\n")
	c.Check(e, DeepEquals, "")
	c.Check(x, DeepEquals, 0)
}

func (s *JobSuite) TestSpawnWithStdin(c *C) {
	s.Job.Args = []string{"cat", "-"}
	s.Job.Stdin = strings.NewReader("stdin")
	s.Spawn()

	o, e, x := s.LinkAndCollect(c)
	c.Check(o, DeepEquals, "stdin")
	c.Check(e, DeepEquals, "")
	c.Check(x, DeepEquals, 0)
}

func (s *JobSuite) TestSpawnWithEnv(c *C) {
	s.Job.Args = []string{"sh"}
	s.Job.Env = append(s.Job.Env, "FOO=bar")
	s.Job.Stdin = strings.NewReader("echo $FOO")
	s.Spawn()

	o, e, x := s.LinkAndCollect(c)
	c.Check(o, DeepEquals, "bar\n")
	c.Check(e, DeepEquals, "")
	c.Check(x, DeepEquals, 0)
}
