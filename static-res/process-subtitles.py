#!/usr/bin/env python3

import argparse
import ass
import datetime
import io
import os
import re
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--file', help='Subtitle file to operate on.', required=True)
parser.add_argument('--operation', help='"add" or "remove".', choices=('add', 'remove'), required=True)
parser.add_argument('--begin', help='Interval begin timestamp as a stringified float (number of seconds).')
parser.add_argument('--end', help='Interval end timestamp as a stringified float (number of seconds).')
args = parser.parse_args()
handle = open(args.file, 'r')
doc = ass.parse(handle.readlines())
handle.close()
begin = datetime.timedelta(seconds=float(args.begin))
end = datetime.timedelta(seconds=float(args.end))
duration = end - begin
assert begin <= end

if args.operation == 'add':
	for e in list(doc.events):
		if e.start > end:                          #  \---int---/
			e.start += duration                #               [---sub---]: Moved forward
			e.end += duration

		elif e.start >= begin and e.start <= end:  #    \-int-/
			e.end += duration                  #  [---sub---]: Extended by interval length

		                                           #  Other cases: No change.
else:
	for e in list(doc.events):
		if e.start > end:                          #  [---int---]
			e.start -= duration                #               [---sub---]: Moved backward
			e.end -= duration

		elif e.start >= begin and e.start <= end:  #  [---int---]
			doc.events.remove(e)               #    [-sub-]: Cut

		elif e.start < begin and e.end > end:      #    [-int-]
			e.end -= duration                  #  [---sub---]: End moved backwards by duration of interval

		elif e.start < begin and e.end >= begin:   #       [---int---]
			e.end = begin                      #  [---sub---]: End clipped to beginning of interval

		elif e.start < end and e.end >= end:       #  [---int---]
			e.start = end                      #       [---sub---]: Beginning clipped to end of interval

		                                           #  Other cases: No change.

doc.dump_file(open(args.file, 'w'))
