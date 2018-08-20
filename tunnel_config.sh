#!/bin/bash

# Takes one argument :
#   name of key file - without .pem extension = $1

# Configure Spark history
ssh -NfL 18080:localhost:18080 $1
# Configure Jupyter notebook
ssh -NfL 48888:localhost:48888 $1
# Configure Ganglia
ssh -NfL 8157:localhost:80 $1
