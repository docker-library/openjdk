[![Build status](https://badge.buildkite.com/ef8f8150a0338d4e54a63c45b0915795dd3410a786aab1500d.svg)](https://buildkite.com/bandsintown/docker-openjdk)
	
# About this Repo

This Git Repo is based on the [official repo](https://github.com/docker-library/openjdk) for Docker OpenJDK images.

We just removed the images not based on Alpine Linux and define [bandsintown/alpine](https://github.com/bandsintown/docker-alpine) image as the base image in order 
to have Consul Template and GoDNSMasq setup.
 