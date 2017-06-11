#!/usr/bin/env python3
# This utility tries to parse a .ass file. If it fails, it errors out.

import argparse
import ass
import datetime
import io
import os
import re
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--file', help='Subtitle file to operate on.', required=True)
args = parser.parse_args()
handle = open(args.file, 'r')
doc = ass.parse(handle.readlines())
handle.close()
