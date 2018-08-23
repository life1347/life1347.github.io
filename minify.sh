#!/bin/bash
htmlmin $1 > $1.min && rm $1 && mv $1.min $1
