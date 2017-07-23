[![dockeri.co](http://dockeri.co/image/bandsintown/openjdk)](https://hub.docker.com/r/bandsintown/openjdk/)

[![Build status](https://badge.buildkite.com/f78e045c0b561ba33f80f3c996ccfe89b49ade24b832f92bfd.svg)](https://buildkite.com/bandsintown/docker-openjdk)
[![GitHub issues](https://img.shields.io/github/issues/bandsintown/docker-openjdk.svg "GitHub issues")](https://github.com/bandsintown/docker-openjdk)
[![GitHub stars](https://img.shields.io/github/stars/bandsintown/docker-openjdk.svg "GitHub stars")](https://github.com/bandsintown/docker-openjdk)
[![Docker layers](https://images.microbadger.com/badges/image/bandsintown/openjdk.svg)](http://microbadger.com/images/bandsintown/openjdk)
	
	
# About this Repo

This Git Repo is based on the [official repo](https://github.com/docker-library/openjdk) for Docker OpenJDK images.

We just removed the images not based on Alpine Linux and define [bandsintown/alpine](https://github.com/bandsintown/docker-alpine) image as the base image in order 
to have Consul Template and GoDNSMasq setup.
 