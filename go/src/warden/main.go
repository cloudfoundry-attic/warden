package main

import (
	"flag"
	"warden/server"
	"warden/server/config"
)

func main() {
	var path string

	flag.StringVar(&path, "config", "config/example.yml", "path to configuration file")

	flag.Parse()

	c := config.InitConfigFromFile(path)
	s := server.NewServer(c)
	s.Start()
}
