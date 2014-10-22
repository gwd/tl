#!/bin/bash
dpkg -r $(dpkg -l | grep xen-upstream | awk '{print $2;}')
