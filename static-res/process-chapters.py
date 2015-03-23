#!/usr/bin/env python3

import argparse
import datetime
import math
import re
import sys
import xml.etree.ElementTree as ET


def stringToTime(stamp):
	stamp = stamp.split(':')
	if len(stamp) != 3:
		raise Exception('Unexpected timestamp format: %s' % (stamp,))
	hours = int(stamp[0])
	minutes = int(stamp[1])
	if '.' in stamp[2]:
		seconds, fracSeconds = stamp[2].split('.')
		seconds = int(seconds)
		fracSeconds = fracSeconds[:6] # We don't care past microsecond.
		fracSeconds += '0' * (6 - len(fracSeconds))  # Make sure we're padded to microsecond resolution.
		microSeconds = int(fracSeconds)
	else:
		seconds = int(stamp[2])
		microSeconds = 0
	return datetime.timedelta(hours=hours, minutes=minutes, seconds=seconds, microseconds=microSeconds)
def timeToString(stamp):
	return '%02d:%02d:%02d.%06d000' % (stamp.seconds // 3600, stamp.seconds % 3600 // 60, stamp.seconds % 60, stamp.microseconds)

parser = argparse.ArgumentParser()
parser.add_argument('--output_fps_numerator', type=int, help='Output FPS numerator.', required=True)
parser.add_argument('--output_fps_denominator', type=int, help='Output FPS denominator.', required=True)
parser.add_argument('--input_total_duration', type=float, help='Total input duration, in seconds.', required=True)
parser.add_argument('--remove_op', type=str, help='Remove OP or not (string "true" or "false").', required=True)
parser.add_argument('--op_begin_fade', type=float, help='OP initial fade-out duration, in seconds.', required=True)
parser.add_argument('--op_end_fade', type=float, help='OP final fade-in duration, in seconds.', required=True)
parser.add_argument('--op_regex', type=str, help='OP chapter name regular expression.', required=True)
parser.add_argument('--remove_ed', type=str, help='Remove ED or not (string "true" or "false").', required=True)
parser.add_argument('--ed_begin_fade', type=float, help='ED initial fade-out duration, in seconds.', required=True)
parser.add_argument('--ed_end_fade', type=float, help='ED final fade-in duration, in seconds.', required=True)
parser.add_argument('--ed_regex', type=str, help='ED chapter name regular expression.', required=True)
args = parser.parse_args()

outputFpsNumerator = args.output_fps_numerator
outputFpsDenominator = args.output_fps_denominator
inputTotalDuration = datetime.timedelta(seconds=args.input_total_duration)
removeOp = args.remove_op == 'true'
opBeginFade = datetime.timedelta(seconds=args.op_begin_fade)
opEndFade = datetime.timedelta(seconds=args.op_end_fade)
opRegex = re.compile(args.op_regex, re.IGNORECASE)
removeEd = args.remove_ed == 'true'
edBeginFade = datetime.timedelta(seconds=args.ed_begin_fade)
edEndFade = datetime.timedelta(seconds=args.ed_end_fade)
edRegex = re.compile(args.ed_regex, re.IGNORECASE)

getFrameAt = lambda dt: round(float(dt.total_seconds()) * float(outputFpsNumerator) / float(outputFpsDenominator))
getVideoSeconds = lambda dt: float(getFrameAt(dt)) * float(outputFpsDenominator) / float(outputFpsNumerator)


class Chapter(object):
	@classmethod
	def getText(cls, node, tag, default=None):
		element = node.find(tag)
		if element is None:
			if default is not None:
				return default
			raise Exception('Cannot find subtag %r in node %r' % (tag, node))
		return element.text
	@classmethod
	def makeSubElement(cls, parent, tag, text):
		element = ET.SubElement(parent, tag)
		element.text = text
		return element
	def __init__(self, node):
		self.uid = self.getText(node, 'ChapterUID').strip()
		self.start = stringToTime(self.getText(node, 'ChapterTimeStart').strip())
		self.hidden = self.getText(node, 'ChapterFlagHidden', default='0').strip()
		self.enabled = self.getText(node, 'ChapterFlagEnabled', default='1').strip()
		self.external = node.find('ChapterSegmentUID') is not None
		self.displays = []
		for display in node.findall('ChapterDisplay'):
			name = self.getText(display, 'ChapterString').strip()
			language = self.getText(display, 'ChapterLanguage', default='').strip()
			self.displays.append([name, language])
	def isOp(self):
		for name, _ in self.displays:
			if opRegex.search(name):
				return True
		return False
	def isEd(self):
		for name, _ in self.displays:
			if edRegex.search(name):
				return True
		return False
	def suffixName(self, suffix):
		for display in self.displays:
			display[0] += suffix
	def toXML(self):
		chapter = ET.Element('ChapterAtom')
		self.makeSubElement(chapter, 'ChapterUID', self.uid)
		self.makeSubElement(chapter, 'ChapterTimeStart', timeToString(self.start))
		self.makeSubElement(chapter, 'ChapterFlagHidden', self.hidden)
		self.makeSubElement(chapter, 'ChapterFlagEnabled', self.enabled)
		for name, language in self.displays:
			element = ET.SubElement(chapter, 'ChapterDisplay')
			self.makeSubElement(element, 'ChapterString', name)
			self.makeSubElement(element, 'ChapterLanguage', language)
		return chapter

chaptersXML = ET.fromstring(sys.stdin.read())
editionEntry = chaptersXML.find('EditionEntry')
if editionEntry is None:
	raise Exception('Cannot find chapters EditionEntry.')
chapterNodes = list(editionEntry.findall('ChapterAtom'))
if not chapterNodes:
	raise Exception('No chapters found in chapter dump')
chapters = []
for c in chapterNodes:
	chapters.append(Chapter(c))
	editionEntry.remove(c)

totalCut = datetime.timedelta()

# Find the ED and remove it.
edExternal = False
if removeEd:
	edIndex = edChapter = None
	for i, c in reversed(list(enumerate(chapters))):
		if c.isEd():
			edIndex = i
			edChapter = c
			break
	if edIndex is None:
		raise Exception('Cannot find ED')
	if edChapter.external:
		chapters.remove(edChapter)
		edExternal = True
	else:
		edChapter.suffixName(' (Cut)')
		edBeginFadeBeginTimestamp = edChapter.start
		edBeginFadeEndTimestamp = edChapter.start + edBeginFade
		edEndFadeEndTimestamp = inputTotalDuration if edIndex == len(chapters) - 1 else chapters[edIndex+1].start
		edEndFadeBeginTimestamp = edEndFadeEndTimestamp - edEndFade
		shortened = edEndFadeBeginTimestamp - edBeginFadeEndTimestamp
		for c in chapters[edIndex+1:]:
			c.start -= shortened
		totalCut += shortened

# Find the OP and remove it.
opExternal = False
if removeOp:
	opIndex = opChapter = None
	for i, c in enumerate(chapters):
		if c.isOp():
			opIndex = i
			opChapter = c
			break
	if opIndex is None:
		raise Exception('Cannot find OP')
	if opChapter.external:
		chapters.remove(opChapter)
		opExternal = True
	else:
		opChapter.suffixName(' (Cut)')
		opBeginFadeBeginTimestamp = opChapter.start
		opBeginFadeEndTimestamp = opChapter.start + opBeginFade
		opEndFadeEndTimestamp = inputTotalDuration if opIndex == len(chapters) - 1 else chapters[opIndex+1].start
		opEndFadeBeginTimestamp = opEndFadeEndTimestamp - opEndFade
		shortened = opEndFadeBeginTimestamp - opBeginFadeEndTimestamp
		for c in chapters[opIndex+1:]:
			c.start -= shortened
		totalCut += shortened

# Output back to XML.
for c in chapters:
	editionEntry.append(c.toXML())
print('<?xml version="1.0"?>')
print('<!-- <!DOCTYPE Chapters SYSTEM "matroskachapters.dtd"> -->')
print(ET.tostring(chaptersXML, encoding='unicode'))

# Output timing information for main script.
def printInfo(var, value):
	print('<!-- makeitsmooth:%s:%s: -->' % (var, value))

opNeeded = removeOp and not opExternal
printInfo('opActuallyRemove', 'true' if opNeeded else 'false')
if opNeeded:
	printInfo('opBeginFadeBeginFrame', getFrameAt(opBeginFadeBeginTimestamp))
	printInfo('opBeginFadeBeginTimestamp', getVideoSeconds(opBeginFadeBeginTimestamp))
	printInfo('opBeginFadeEndFrame', getFrameAt(opBeginFadeEndTimestamp))
	printInfo('opBeginFadeEndTimestamp', getVideoSeconds(opBeginFadeEndTimestamp))
	printInfo('opBeginFadeFrameCount', getFrameAt(opBeginFadeEndTimestamp) - getFrameAt(opBeginFadeBeginTimestamp))
	printInfo('opBeginFadeDuration', getVideoSeconds(opBeginFadeEndTimestamp - opBeginFadeBeginTimestamp))
	printInfo('opEndFadeBeginFrame', getFrameAt(opEndFadeBeginTimestamp))
	printInfo('opEndFadeBeginTimestamp', getVideoSeconds(opEndFadeBeginTimestamp))
	printInfo('opEndFadeEndFrame', getFrameAt(opEndFadeEndTimestamp))
	printInfo('opEndFadeEndTimestamp', getVideoSeconds(opEndFadeEndTimestamp))
	printInfo('opEndFadeFrameCount', getFrameAt(opEndFadeEndTimestamp) - getFrameAt(opEndFadeBeginTimestamp))
	printInfo('opEndFadeDuration', getVideoSeconds(opEndFadeEndTimestamp - opEndFadeBeginTimestamp))

edNeeded = removeEd and not edExternal
printInfo('edActuallyRemove', 'true' if edNeeded else 'false')
if edNeeded:
	printInfo('edBeginFadeBeginFrame', getFrameAt(edBeginFadeBeginTimestamp))
	printInfo('edBeginFadeBeginTimestamp', getVideoSeconds(edBeginFadeBeginTimestamp))
	printInfo('edBeginFadeEndFrame', getFrameAt(edBeginFadeEndTimestamp))
	printInfo('edBeginFadeEndTimestamp', getVideoSeconds(edBeginFadeEndTimestamp))
	printInfo('edBeginFadeFrameCount', getFrameAt(edBeginFadeEndTimestamp) - getFrameAt(edBeginFadeBeginTimestamp))
	printInfo('edBeginFadeDuration', getVideoSeconds(edBeginFadeEndTimestamp - edBeginFadeBeginTimestamp))
	printInfo('edEndFadeBeginFrame', getFrameAt(edEndFadeBeginTimestamp))
	printInfo('edEndFadeBeginTimestamp', getVideoSeconds(edEndFadeBeginTimestamp))
	printInfo('edEndFadeEndFrame', getFrameAt(edEndFadeEndTimestamp))
	printInfo('edEndFadeEndTimestamp', getVideoSeconds(edEndFadeEndTimestamp))
	printInfo('edEndFadeFrameCount', getFrameAt(edEndFadeEndTimestamp) - getFrameAt(edEndFadeBeginTimestamp))
	printInfo('edEndFadeDuration', getVideoSeconds(edEndFadeEndTimestamp - edEndFadeBeginTimestamp))

printInfo('totalCutDuration', getVideoSeconds(totalCut))
printInfo('outputTotalDuration', getVideoSeconds(inputTotalDuration - totalCut))
