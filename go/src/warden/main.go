package main

import (
	"flag"
	steno "github.com/cloudfoundry/gosteno"
	"os"
	"warden/server"
	"warden/server/config"
)

func SetupLogger(c *config.Config) {
	level, err := steno.GetLogLevel(c.Logging.Level)
	if err != nil {
		panic(err)
	}

	sinks := make([]steno.Sink, 0)
	if c.Logging.File != "" {
		sinks = append(sinks, steno.NewFileSink(c.Logging.File))
	} else {
		sinks = append(sinks, steno.NewIOSink(os.Stdout))
	}

	if c.Logging.Syslog != "" {
		sinks = append(sinks, steno.NewSyslogSink(c.Logging.Syslog))
	}

	x := &steno.Config{
		Sinks: sinks,
		Codec: steno.NewJsonCodec(),
		Level: level,
	}

	steno.Init(x)
}

func main() {
	var path string

	flag.StringVar(&path, "config", "config/example.yml", "path to configuration file")

	flag.Parse()

	c := config.InitConfigFromFile(path)
	SetupLogger(c)

	s := server.NewServer(c)
	s.Start()
}
