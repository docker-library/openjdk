#!/bin/bash
docker build -t openjdk:8-windowsservercore windowsservercore
docker build -t openjdk:8-nanoserver nanoserver
docker run openjdk:8-windowsservercore java -version
docker run openjdk:8-nanoserver java -version
