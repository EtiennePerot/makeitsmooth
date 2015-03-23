#!/usr/bin/env bash

set -e

reloadDefaultConfig() {
	# All of these values are overridable by command-line-specified config files, and by per-directory config files.

	# General settings
	OUTPUT_DIR='/tmp/smooth' # Output directory for video files. All files will be dumped as-is with no deeper hierarchy.
	OUTPUT_HEIGHT=''         # Vertical resolution of the output video. The aspect ratio will be kept, though the width will
	                         # be rounded to the nearest multiple of 4. If OUTPUT_HEIGHT is blank, no resizing occurs.

	# Motion interpolation settings
	INTERFRAME_ENABLE=true        # Turn on motion interpolation through InterFrame.
	OUTPUT_FPS_NUMERATOR=60       # Numerator of the target FPS.
	OUTPUT_FPS_DENOMINATOR=1      # Denominator of the target FPS.
	OUTPUT_FPS_MULTIPLIER=''      # If set, the target framerate is instead determined by multiplying the input framerate
	                              # with this value.
	INTERFRAME_PRESET='Animation' # InterFrame preset name.

	# Encoding settings
	CORES="$(nproc)"                              # Number of CPU cores to use. Half of the cores will go to x264, and the
	                                              # other half of the cores will go to AviSynth.
	AVISYNTH_MEMORY_MB=1024                       # Maximum allowed memory usage by AviSynth, in megabytes.
	X264_PROFILE='high10'                         # x264 profile setting.
	X264_TUNE='animation'                         # x264 tuning setting.
	X264_PRESET='slow'                            # x264 preset to select encoding speed and efficiency.
	X264_FLAGS=(--crf 15.5 --qpmin 12 --qpmax 28) # Extra x264 flags.

	# OP/ED removal settings
	REMOVE_OP=false                    # Turn on OP removal.
	OP_BEGIN_FADE=3                    # Initial seconds of the OP to apply the fade-out effect to.
	OP_END_FADE=3                      # Final seconds of the OP to apply the fade-in effect to.
	OP_REGEX='^(OP|Opening|Credits)$'  # Regular expression matching the OP chapter name.
	OP_FIXED_TIME_ENABLE=false         # If true, OP detection is fixed to the timestamps below.
	OP_FIXED_TIME_START=0              # Timestamp at which the OP begins, in seconds.
	OP_FIXED_TIME_END=89.9             # Timestamp at which the OP ends, in seconds.
	REMOVE_ED=false                    # Turn on ED removal.
	ED_BEGIN_FADE=3                    # Initial seconds of the ED to apply the fade-out effect to.
	ED_END_FADE=3                      # Final seconds of the ED to apply the fade-in effect to.
	ED_REGEX='^(ED|Ending|Credits)$'   # Regular expression matching the ED chapter name.

	# Audio/subtitle handling settings
	# Strategies can be either "all", "none", a number for 0-based stream number, "default" for whatever streams are marked as default,
	# "forced" for whatever streams are marked as forced, "lang:foo" where "foo" is the language ("jpn", "eng", etc), or "title:regex"
	# (where regex is matched against stream title (not the whole file title!)).
	AUDIO_SELECT_STRATEGY='all'           # Audio stream strategy
	SUB_SELECT_STRATEGY='all'             # Subtitle stream strategy
	AUDIO_MUST_MATCH=true                 # Whether or not we should give up if no audio streams match the strategy above
	                                      # and there are a nonzero number of audio streams in the file.
	                                      # Ignored if the strategy is "none".
	SUB_MUST_MATCH=true                   # The same, for subtitle streams.
	SUB_INJECT_MERGE_STRATEGY='none'      # Strategy for picking which subtitle streams to merge injected subtitles with.
	                                      # The injected subtitles will also be added as a separate subtitle stream regardless of this.
	                                      # "0" for example means the injected subtitles will be merged with the first subtitle stream that matches SUB_SELECT_STRATEGY.
	                                      # If you want the injected subtitles to be in a separate subtitle stream only, set this option to "none" and set
	                                      # SUB_INJECT_SEPARATE=true.
	SUB_INJECT_SEPARATE=true              # Causes the injected subtitle to be injected as a separate subtitle stream with the "default" flag set.
	SUB_INJECT=false                      # Turn on subtitle injection.
	SUB_INJECT_DIRECTORY=''               # Directory to look into for injecting subtitles.
	SUB_INJECT_DIRECTORY_INCLUDESOP=true  # true if the subtitles to inject contain the OP subtitles.
	SUB_INJECT_DIRECTORY_INCLUDESED=true  # true if the subtitles to inject contain the ED subtitles.
	SUB_INJECT_LANGUAGE=''                # Language code of the subtitles to inject. If not provided, no language code will be set.
	SUB_INJECT_EXCLUDE=''                 # Value of the --exclude flag to submerger.
	SUB_MUST_INJECT=false                 # If true, not being able to find a subtitle file to inject for a video file will be considered an error.
	                                      # Ignored if the strategy is "none" and SUB_INJECT_SEPARATE is false.
	BURN_SUBTITLES=false                  # Burn subtitles to video. Either "true" (subtitles burned on video, no subtitles included in container),
	                                      # "false" (no burn, subtitles included in container), or "both" (subtitles burned on video and included in container).
	BURN_SUBTITLES_BURN_STRATEGY=0        # Subtitles to burn. No effect if BURN_SUBTITLES is "false". Note that if you have SUB_INJECT_SEPARATE=true, the
	                                      # first subtitle stream is the injected one, and all other subtitle streams that were previously present in the file
	                                      # are now offset by one. FIXME: Make it work.
	BURN_SUBTITLES_KEEP_STRATEGY='all'    # Subtitles to keep in the container after burning. No effect if BURN_SUBTITLES is "false". FIXME: Make that work
}

reloadDefaultConfig

# If one of these files is found next to one of the files to process, it will be sourced prior to processing the file.
# The file will be sourced with the MAKEITSMOOTH_THIS_FILE variable set to the full path of the file.
PERDIR_OVERRIDE_CONFIGS=('.makeitsmooth' '.makeitsmooth/makeitsmooth.config')
scriptDir="$(dirname "$BASH_SOURCE")"
scriptDir="$(cd "$scriptDir" && pwd)"
configFile="$scriptDir/config"
resourceDir="$scriptDir/res"
staticResourceDir="$scriptDir/static-res"
scratchDir="$scriptDir/scratch"
processChapters="$staticResourceDir/process-chapters.py"
processSubtitles="$staticResourceDir/process-subtitles.py"
wineTar='wine-1.7.12.tar.bz2'
avisynthBuild7z='avisynth_20130928.7z'
devilBuildZip='DevIL-EndUser-x86-1.7.8.zip'
interframeFolder='InterFrame-2.6.0'
interframeZip="$interframeFolder.zip"
avs2yuvExe='avs2yuv.exe'
ffms2Root='ffms2-2.18-rc1'
ffms27z="$ffms2Root.7z"
fontreg7z='fontreg-2.1.3-redist.7z'
fontreg7zBinary='bin.x86-32/FontReg.exe'
xyVSFilter7z='xy-VSFilter_3.0.0.211.7z'
resources=(
	"https://www.dropbox.com/s/6f56nvqvxrde22q/$avisynthBuild7z|ea7b1ddfadd98f82b21d3315f53482445292fb9d"
	"http://downloads.sourceforge.net/openil/DevIL%20Win32/1.7.8/$devilBuildZip|45ddef5ceea884ad2b36edee37af747618afe641"
	"http://mirrors.ibiblio.org/wine/source/1.7/$wineTar|142def53c2e7e46418fd37426232d1524f09c73b"
	"http://www.spirton.com/uploads/InterFrame/$interframeZip|fbbb93e3ad798df704523e4210a91796723e47f7"
	"http://akuvian.org/src/avisynth/avs2yuv/$avs2yuvExe|4abe0de0ec66d8fe43910ba7794b837512bff1fc"
	"https://ffmpegsource.googlecode.com/files/$ffms27z|f2d68b5f67d74c73e9707a0919fe594be49a2168"
	"http://code.kliu.org/misc/fontreg/$fontreg7z|a7ded5853f8ea326e944fa111ab15da0fec4c023"
	"http://xy-vsfilter.googlecode.com/files/$xyVSFilter7z|fd76a4032577c5962271ba93aebfe49e247a1e03"
)
wineDir="$scratchDir/wine"
wineBuildDir="$wineDir/build"
wineBinary="$wineBuildDir/wine"
winePrefix="$wineDir/prefix"
wineDriveC="$winePrefix/drive_c"
wineWindows="$wineDriveC/windows"
wineSystem32="$wineWindows/system32"
wineProgramFiles1="$wineDriveC/Program Files (x86)"
wineProgramFiles2="$wineDriveC/Program Files"
wineProgramFiles1Windows="C:\\Program Files (x86)"
wineProgramFiles2Windows="C:\\Program Files"
wineFonts="$wineWindows/Fonts"
interframeExtract="$scratchDir/$interframeFolder"
interframePlugins=("$interframeExtract/InterFrame2.avsi" "$interframeExtract/Dependencies/svpflow1.dll" "$interframeExtract/Dependencies/svpflow2.dll" "$interframeExtract/Dependencies/svpflow_cpu.dll")
avisynthDll="$wineSystem32/avisynth.dll"
devilDll="$wineSystem32/DevIL.dll"
avs2yuvBinary="$resourceDir/$avs2yuvExe"
ffms2Extract="$scratchDir/$ffms2Root"
ffms2Plugins=("$ffms2Extract/FFMS2.avsi" "$ffms2Extract/x86/ffms2.dll")
fontregExtractDirectory="$scratchDir/fontreg"
fontregBinary="$fontregExtractDirectory/$fontreg7zBinary"
xyVSFilterDllFilename='VSFilter.dll'
submergerBinary="$staticResourceDir/submerger/submerger"
avsTemplate="$staticResourceDir/template.avs"
wineInputFilename='__input.mkv'
wineInputBurnedSubtitlesFilename='__burn.ass'
avs2yuvInputFilename='input.avs'
intermediateChaptersFileSuffix='.chapters.xml'
corefonts=(
	'arialbd.ttf|0d99c9d151db525c20b8209b9f0ee1ce812a961c'
	'arialbi.ttf|0aba42fc6e5b1e78992414f5c4df31376f90f0e2'
	'ariali.ttf|d205d443f4431600378adaa92a29cc0396508919'
	'arial.ttf|2c5cb7cfa19eea5d90c375dc0f9f8e502ea97f0c'
	'ariblk.ttf|49560b47dac944923a6c918c75f27fbe8a3054c5'
	'comicbd.ttf|5518f0bdebe7212d10492ab6f4fff9b0230c3cbe'
	'comic.ttf|d17fae7a6628e2bc4c31a2074b666a775eed9055'
	'courbd.ttf|39b43bf424ac193259b3787764c1cdd7a7e2242c'
	'courbi.ttf|c5f4818fa6876e93f043a209597bcb39c57e43ca'
	'couri.ttf|74941cc95734772f8b17aeec33e9a116f94a26ae'
	'cour.ttf|9c5be4c1f151257798602aa74a7937dcead5db1f'
	'georgiab.ttf|3ccf584caad7dfaf07a2b492e6e27dfe642c6ba0'
	'georgiai.ttf|f6bafcca21153f02b4449fc8949cdd5786bb2992'
	'georgia.ttf|5d69d55862471d18f1c22132a44f05291134cbf4'
	'georgiaz.ttf|328b246b57108d5f175eb9a4df8f613b7207d0bf'
	'impact.ttf|1cc231f6ba7e2c141e28db4eac92b211d4033df6'
	'timesbd.ttf|f67a30f4db2ff469ed5b2c9830d031cb4b3174b4'
	'timesbi.ttf|e997a0bf7a322c7ba5d4bde9251129dee3f66119'
	'timesi.ttf|5f896ef096ad01f495cefc126e963b2cd6638fab'
	'times.ttf|d9d9ad4ba85fcd9dbe69e7866613756f1dbb4e97'
	'trebucbd.ttf|b54b5fa32a884b4297b2343efdc745d0755cc7d1'
	'trebucbi.ttf|bc377a42afee7f73f0b80e2ed6e0d18edbd4f8fd'
	'trebucit.ttf|2614ce1c336f8568b9bf0c14752edfe1819a072f'
	'trebuc.ttf|6480f383a9cd92c8d75ac11ef206c53e3233abb2'
	'verdanab.ttf|fe5e9cfe72f1cbf07b4190f7fc4702cd15f452d1'
	'verdanai.ttf|3ac316b55334e70a6993ded91328682733c4d133'
	'verdana.ttf|ba19d57e11bd674c1d8065e1736454dc0a051751'
	'verdanaz.ttf|09aff891c626fe7d3b878f40a6376073b90d4fde'
	'webdings.ttf|bc1382a14358f747cbd3ff54676950231f67c95a'
)
fontExtensions=(fon ttf ttc otf)

if [ -z "$1" ]; then
	echo "Usage: $0 n1 n2 ... [-c configfile2 n3 n4 n5 ... [-c configfile3 n6 n7 ...]]"
	echo " In the above line, n1 and n2 would be processed using the default configuration file '$configFile',"
	echo ' n3, n4 and n5 would be processed using configfile2, and n6, n7 would be processed using configfile3.'
	echo ' nX can be an mkv file, or a directory which will be resursively searched for *.mkv files.'
	exit 0
fi

echo 'Making sure we have all resources...'
for res in "${resources[@]}"; do
	url="$(echo "$res" | cut -d'|' -f1)"
	sha1="$(echo "$res" | cut -d'|' -f2)"
	path="$resourceDir/$(basename "$url")"
	while [ ! -f "$path" -o "$(sha1sum "$path" | cut -d' ' -f1 || true)" != "$sha1" ]; do
		rm -f "$path"
		echo "(Re-)downloading '$url' to '$path'..."
		wget "$url" -O "$path" || true
	done
done

echo 'Taking care of Wine...'
if [ ! -x "$wineBinary" ]; then
	echo 'Compiling wine...'
	rm -rf "$wineDir"
	mkdir -p "$wineBuildDir"
	pushd "$wineBuildDir" &> /dev/null
		tar xf "$resourceDir/$wineTar" --strip-components=1
		./configure
		make -j"$(($CORES * 2))"
	popd &> /dev/null
	if [ ! -x "$wineBinary" ]; then
		echo 'Error: Wine compilation failed.'
		exit 1
	fi
fi
export WINE="$wineBinary"
export WINEARCH='win32'
export WINEPREFIX="$winePrefix"

echo 'Taking care of the Wine prefix...'
if [ ! -d "$winePrefix" ]; then
	echo 'Launching winecfg. Close it when the Wine prefix is set up.'
	"$wineBinary" winecfg
	if [ ! -d "$winePrefix" ]; then
		echo "Could not create wine prefix at '$winePrefix'."
		exit 1
	fi
fi

echo 'Taking care of corefonts...'
checkCorefonts() {
	if [ ! -d "$wineFonts" ]; then
		echo "Could not find Wine font directory '$wineFonts'."
		return 1
	fi
	checkCorefontsReturnCode=0
	pushd "$wineFonts" &> /dev/null
		for font in *; do
			isCorefont=false
			for corefont in "${corefonts[@]}"; do
				if echo "$font" | grep -qxiF "$(echo "$corefont" | cut -d'|' -f1)"; then
					isCorefont=true
					break
				fi
			done
			if [ "$isCorefont" != true ]; then
				rm -f "$font"
			fi
		done
		for corefont in "${corefonts[@]}"; do
			fontFileFound="$(find -iname "$(echo "$corefont" | cut -d'|' -f1)")"
			if [ -z "$fontFileFound" ]; then
				echo "Could not find corefont: '$font'."
				checkCorefontsReturnCode=1
			elif [ "$(cat "$fontFileFound" | sha1sum | cut -d' ' -f1)" != "$(echo "$corefont" | cut -d'|' -f2)" ]; then
				echo "Corefont '$fontFileFound' does not match expected sha1sum. Deleting."
				rm -f "$fontFileFound"
				checkCorefontsReturnCode=1
			fi
		done
	popd &> /dev/null
	return "$checkCorefontsReturnCode"
}
ensureCorefonts() {
	if ! checkCorefonts &> /dev/null; then
		rm -f "$wineFonts"/*
		if ! winetricks corefonts; then
			echo 'Could not install corefonts in prefix.'
			return 1
		fi
		if ! checkCorefonts; then
			return 1
		fi
	fi
}
if ! ensureCorefonts; then
	exit 1
fi

echo 'Taking care of InterFrame...'
if [ ! -d "$interframeExtract" ]; then
	pushd "$scratchDir" &> /dev/null
		unzip "$resourceDir/$interframeZip"
	popd &> /dev/null
	if [ ! -d "$interframeExtract" ]; then
		echo 'Error: Failed to extract files from InterFrame.'
		exit 1
	fi
fi

echo 'Taking care of FFMS2...'
if [ ! -d "$ffms2Extract" ]; then
	pushd "$scratchDir" &> /dev/null
		7z x "$resourceDir/$ffms27z"
	popd &> /dev/null
	if [ ! -d "$ffms2Extract" ]; then
		echo 'Error: Failed to extract files from ffms2.'
		exit 1
	fi
fi

echo 'Taking care of FontReg...'
if [ ! -f "$fontregBinary" ]; then
	mkdir -p "$fontregExtractDirectory"
	pushd "$fontregExtractDirectory" &> /dev/null
		7z x "$resourceDir/$fontreg7z"
	popd &> /dev/null
	if [ ! -f "$fontregBinary" ]; then
		echo 'Error: Failed to extract files from fontreg.'
		exit 1
	fi
fi

echo 'Taking care of AviSynth...'
if [ ! -f "$avisynthDll" ]; then
	pushd "$(dirname "$avisynthDll")" &> /dev/null
		7z x "$resourceDir/$avisynthBuild7z"
	popd &> /dev/null
	if [ ! -f "$avisynthDll" ]; then
		echo 'Failed to extract avisynth.'
		exit 1
	fi
fi
if [ ! -f "$devilDll" ]; then
	pushd "$(dirname "$devilDll")" &> /dev/null
		unzip "$resourceDir/$devilBuildZip"
	popd &> /dev/null
	if [ ! -f "$devilDll" ]; then
		echo 'Failed to extract DevIL.'
		exit 1
	fi
fi
aviSynthDir="$wineProgramFiles1/AviSynth"
aviSynthDirWindows="$wineProgramFiles1Windows/AviSynth"
if [ ! -d "$wineProgramFiles1" ]; then
	aviSynthDir="$wineProgramFiles2/AviSynth"
	aviSynthDirWindows="$wineProgramFiles2Windows\\AviSynth"
fi
aviSynthPluginsDir="$aviSynthDir/plugins"
aviSynthPluginsDirWindows="$aviSynthDirWindows\\plugins"
mkdir -p "$aviSynthPluginsDir"
cp --no-clobber "${interframePlugins[@]}" "${ffms2Plugins[@]}" "$aviSynthPluginsDir"
wineInputFile="$wineDriveC/$wineInputFilename"
avs2yuvInputFile="$wineDriveC/$avs2yuvInputFilename"
avs2yuvInputWindowsFile="C:\\$avs2yuvInputFilename"
burnedSubtitlesFile="$wineDriveC/$wineInputBurnedSubtitlesFilename"

echo 'Taking care of xy-VSFilter...'
xyVSFilterDllFile="$aviSynthPluginsDir/$xyVSFilterDllFilename"
if [ ! -f "$xyVSFilterDllFile" ]; then
	pushd "$aviSynthPluginsDir" &> /dev/null
		7z x "$resourceDir/$xyVSFilter7z"
	popd &> /dev/null
	if [ ! -f "$xyVSFilterDllFile" ]; then
		echo 'Failed to extract files from xy-VSFilter.'
		exit 1
	fi
fi

echo 'Taking care of submerger...'
if ! "$submergerBinary" --help &> /dev/null; then
	pushd "$scriptDir" &> /dev/null
		git submodule update --init --recursive
	popd &> /dev/null
fi

echo 'Checking command-line tools...'
for cmd in ffmpeg ffprobe mkvextract mkvmerge; do
	if ! which "$cmd" &> /dev/null; then
		echo "Error: Cannot find '$cmd' in '$PATH'."
		exit 1
	fi
done

echo 'Ready to start.'

regexEscape() {
	sed -r 's/[][\(\)\\^$.*+?|{}]/\\\0/g'
}

cutExtension() {
	sed -r 's/\.[^.]+$//'
}

guessEpisodeNumber() {
	# This parser has seen some serious sh*t. Correctly supports things like:
	#   01. Foo 2.mkv
	#   01. Foo - Season 2.mkv
	#   Foo 2 - 01.mkv
	#   Foo - Season 2 - ep 01.mkv
	#   Foo - Season 2 - 01.mkv
	#   Foo - Season 2 - 01 [123456].mkv
	#   Foo [Season 2] [x264] [01] [123456].mkv
	#   Foo [Season 2] [1080p] [x264] [EP 01] [123456].mkv
	#   foo.s02e01.x264.mkv
	cutExtension | sed -r 's/^((.*[^[0-9a-z])?((S[0-9]{1,2})?EP?[-._ ]?)?([0-9]{2,3})([^]0-9a-z].*)?|.*\[(EP?[-._ ]?)?([0-9]{2,3})].*)$/\5\8/i' | sed -r 's/^0+//' | grep -P "^[0-9]+$" || true
}

getClosestFile() {
	# Usage: getClosestFile originalFile matchDir
	# Will attempt to determine the closest file to originalFile in matchDir, based on (in order):
	#   - Exact filename match
	#   - Exact filename prefix match
	#   - Exact filename-minus-extension prefix match
	#   - Filename substring match
	#   - Filename-minus-extension substring match
	#   - Episode-number-extraction match
	# The function will always return success.
	# The actual success criterion is whether anything was output to stdout.
	getClosestFileOriginalFile="$(basename "$1")"
	getClosestFileMatchDir="$2"
	getClosestFileMatchFiles=()
	pushd "$getClosestFileMatchDir" &> /dev/null
		getClosestFileMatchFiles=(*)
	popd &> /dev/null
	if [ "${#getClosestFileMatchFiles[@]}" -eq 0 ]; then
		return 0
	fi
	getClosestFileRegexes=(
		"^($(echo "$getClosestFileOriginalFile" | regexEscape))$"               # Exact filename match
		"^($(echo "$getClosestFileOriginalFile" | regexEscape))"                # Exact filename prefix match
		"^($(echo "$getClosestFileOriginalFile" | cutExtension | regexEscape))" # Exact filename-minus-extension prefix match
		"$(echo "$getClosestFileOriginalFile" | regexEscape)"                   # Filename substring match
		"$(echo "$getClosestFileOriginalFile" | cutExtension | regexEscape)"    # Filename-minus-extension substring match
	)
	for getClosestFileRegex in "${getClosestFileRegexes[@]}"; do
		for getClosestFileF in "${getClosestFileMatchFiles[@]}"; do
			if echo "$getClosestFileF" | grep -qiP "$getClosestFileRegex"; then
				echo "$getClosestFileMatchDir/$getClosestFileF"
				return 0
			fi
		done
	done
	# Fall back to episode-number-guess matching.
	getClosestFileEpNumber="$(echo "$getClosestFileOriginalFile" | guessEpisodeNumber)"
	if [ -n "$getClosestFileEpNumber" ]; then
		for getClosestFileF in "${getClosestFileMatchFiles[@]}"; do
			if [ "$(echo "$getClosestFileF" | guessEpisodeNumber)" == "$getClosestFileEpNumber" ]; then
				echo "$getClosestFileMatchDir/$getClosestFileF"
				return 0
			fi
		done
	fi
}

convert() {
	cleanupFiles=()
	cleanup() {
		rm -rf "${cleanupFiles[@]}"
		# cleanupFiles may contain fonts that overwrote the corefonts one.
		# We must re-get missing corefonts.
		if ! ensureCorefonts; then
			echo 'Cleanup failed to ensure corefonts consistency.'
			exit 1
		fi
	}
	fail() {
		cleanup
		echo "$@"
	}
	inputFile="$1"
	intermediateOutputDir="$2"
	cleanupFiles+=("$intermediateOutputDir")
	outputFile="$3"
	tempMuxingFile="$intermediateOutputDir/mux.mkv"
	cleanupFiles+=("$tempMuxingFile")

	# Streams directories.
	rm -rf "$intermediateOutputDir"
	temporaryVideoFile="$intermediateOutputDir/video.264"
	tempAudioDirectory="$intermediateOutputDir/audio"
	tempAttachmentsDirectory="$intermediateOutputDir/attachments"
	tempAttachmentsFontsDirectory="$intermediateOutputDir/attachments-fonts"
	tempSubtitlesDirectory="$intermediateOutputDir/subtitles"
	temporaryChaptersFile="$intermediateOutputDir/chapters.xml"
	mkdir -p "$tempAudioDirectory" "$tempAttachmentsDirectory" "$tempAttachmentsFontsDirectory" "$tempSubtitlesDirectory"

	# Determine file info.
	ffVideoStreams="$(ffprobe -show_streams -select_streams v "$inputFile" 2>/dev/null)"
	if [ "$?" != 0 ]; then
		fail "ffprobe failed to read video information from '$inputFile'."
		return 1
	fi
	if [ "$(echo "$ffVideoStreams" | grep '^sample_aspect_ratio=' | wc -l)" != 1 ]; then
		fail "Video file '$inputFile' either has no video stream, or has more than one. Cannot proceed."
		return 1
	fi
	sampleAspectRatio="$(echo "$ffVideoStreams" | grep '^sample_aspect_ratio=' | cut -d= -f2)"
	inputFpsNumerator="$(echo "$ffVideoStreams" | grep '^avg_frame_rate=' | cut -d= -f2 | cut -d/ -f1)"
	inputFpsDenominator="$(echo "$ffVideoStreams" | grep '^avg_frame_rate=' | cut -d= -f2 | cut -d/ -f2)"
	inputHeight="$(echo "$ffVideoStreams" | grep '^height=' | cut -d= -f2)"
	if [ "$INTERFRAME_ENABLE" == true ]; then
		if [ -n "$OUTPUT_FPS_MULTIPLIER" ]; then
			outputFpsNumerator="$(python3 -c "import fractions; print((fractions.Fraction($inputFpsNumerator, $inputFpsDenominator) * fractions.Fraction($OUTPUT_FPS_MULTIPLIER).limit_denominator()).numerator)")"
			outputFpsDenominator="$(python3 -c "import fractions; print((fractions.Fraction($inputFpsNumerator, $inputFpsDenominator) * fractions.Fraction($OUTPUT_FPS_MULTIPLIER).limit_denominator()).denominator)")"
		else
			outputFpsNumerator="$OUTPUT_FPS_NUMERATOR"
			outputFpsDenominator="$OUTPUT_FPS_DENOMINATOR"
		fi
	else
		outputFpsNumerator="$inputFpsNumerator"
		outputFpsDenominator="$inputFpsDenominator"
	fi
	ffFormatInfo="$(ffprobe -show_format "$inputFile" 2>/dev/null || true)"
	if [ "$?" != 0 ]; then
		fail "ffprobe failed to read format information from '$inputFile'."
		return 1
	fi
	inputTotalDuration="$(echo "$ffFormatInfo" | grep '^duration=' | cut -d= -f2 | cut -d/ -f2)"
	# outputTotalDuration may be overridden by OP/ED removal.
	outputTotalDuration="$inputTotalDuration"
	inputTitle="$(echo "$ffFormatInfo" | grep '^TAG:title=' | cut -d= -f2-)"
	mkvChapters="$(mkvextract chapters "$inputFile")"
	if [ -z "$mkvChapters" ]; then
		echo "Warning: No chapters found in '$inputFile'. Will not remove OP nor ED."
		opActuallyRemove=false
		edActuallyRemove=false
		chaptersMkvMergeCommand=()
	else
		if [ "$REMOVE_OP" == true -o "$REMOVE_ED" == true ]; then
			if [ "$?" != 0 ]; then
				fail "Could not extract chapters from '$inputFile', and OP/ED removal was requested. Perhaps the file has no chapters?"
				return 1
			fi
			chaptersInfo="$(echo "$mkvChapters" | "$processChapters" --output_fps_numerator "$outputFpsNumerator" --output_fps_denominator "$outputFpsDenominator" --input_total_duration "$inputTotalDuration" --remove_op "$REMOVE_OP" --op_begin_fade "$OP_BEGIN_FADE" --op_end_fade "$OP_END_FADE" --op_regex "$OP_REGEX" --remove_ed "$REMOVE_ED" --ed_begin_fade "$ED_BEGIN_FADE" --ed_end_fade "$ED_END_FADE" --ed_regex "$ED_REGEX")"
			if [ "$?" != 0 ]; then
				fail "Could not process chapters from '$inputFile'."
				return 1
			fi
			echo "OP/ED debugging information:"
			echo "$chaptersInfo" | grep 'makeitsmooth:' | cut -d: -f2,3 | sed 's/^/  /g'
			parseChapterValue() {
				echo "$chaptersInfo" | grep "makeitsmooth:$1:" | cut -d: -f3
			}
			opActuallyRemove="$(parseChapterValue opActuallyRemove)"
			opBeginFadeBeginFrame="$(parseChapterValue opBeginFadeBeginFrame)"
			opBeginFadeBeginTimestamp="$(parseChapterValue opBeginFadeBeginTimestamp)"
			opBeginFadeEndFrame="$(parseChapterValue opBeginFadeEndFrame)"
			opBeginFadeEndTimestamp="$(parseChapterValue opBeginFadeEndTimestamp)"
			opBeginFadeFrameCount="$(parseChapterValue opBeginFadeFrameCount)"
			opBeginFadeDuration="$(parseChapterValue opBeginFadeDuration)"
			opEndFadeBeginFrame="$(parseChapterValue opEndFadeBeginFrame)"
			opEndFadeBeginTimestamp="$(parseChapterValue opEndFadeBeginTimestamp)"
			opEndFadeEndFrame="$(parseChapterValue opEndFadeEndFrame)"
			opEndFadeEndTimestamp="$(parseChapterValue opEndFadeEndTimestamp)"
			opEndFadeFrameCount="$(parseChapterValue opEndFadeFrameCount)"
			opEndFadeDuration="$(parseChapterValue opEndFadeDuration)"
			edActuallyRemove="$(parseChapterValue edActuallyRemove)"
			edBeginFadeBeginFrame="$(parseChapterValue edBeginFadeBeginFrame)"
			edBeginFadeBeginTimestamp="$(parseChapterValue edBeginFadeBeginTimestamp)"
			edBeginFadeEndFrame="$(parseChapterValue edBeginFadeEndFrame)"
			edBeginFadeEndTimestamp="$(parseChapterValue edBeginFadeEndTimestamp)"
			edBeginFadeFrameCount="$(parseChapterValue edBeginFadeFrameCount)"
			edBeginFadeDuration="$(parseChapterValue edBeginFadeDuration)"
			edEndFadeBeginFrame="$(parseChapterValue edEndFadeBeginFrame)"
			edEndFadeBeginTimestamp="$(parseChapterValue edEndFadeBeginTimestamp)"
			edEndFadeEndFrame="$(parseChapterValue edEndFadeEndFrame)"
			edEndFadeEndTimestamp="$(parseChapterValue edEndFadeEndTimestamp)"
			edEndFadeFrameCount="$(parseChapterValue edEndFadeFrameCount)"
			edEndFadeDuration="$(parseChapterValue edEndFadeDuration)"
			totalCutDuration="$(parseChapterValue totalCutDuration)"
			outputTotalDuration="$(parseChapterValue outputTotalDuration)"
			echo "$chaptersInfo" | grep -v 'makeitsmooth:' > "$temporaryChaptersFile"
		else
			echo "$mkvChapters" > "$temporaryChaptersFile"
		fi
		chaptersMkvMergeCommand=(--chapters "$temporaryChaptersFile")
	fi


	streamMatchesRules() {
		# First argument is strategy, second argument is zero-based stream index.
		# This uses "if cond then return 0 else return 1"-type expressions so that this still works with bash mode -e.
		if [ "$1" == 'all' ]; then
			return 0
		elif [ "$1" == 'none' ]; then
			return 1
		elif [ "$1" == 'default' ]; then
			if [ "$currentStreamDefault" == 1 -o "$currentStreamDefault" == true -o "$currentStreamDefault" == yes ]; then
				return 0
			else
				return 1
			fi
		elif [ "$1" == 'forced' ]; then
			if [ "$currentStreamForced" == 1 -o "$currentStreamForced" == true -o "$currentStreamForced" == yes ]; then
				return 0
			else
				return 1
			fi
		elif echo "$1" | grep -qP '^[0-9]+$'; then
			if [ "$1" -eq "$2" ]; then
				return 0
			else
				return 1
			fi
		elif [[ "$1" == lang:* ]]; then
			if [ "$currentStreamLanguage" == "$(echo "$1" | cut -d: -f2-)" ]; then
				return 0
			else
				return 1
			fi
		elif [[ "$1" == title:* ]]; then
			if echo "$currentStreamTitle" | grep -qP "$(echo "$1" | cut -d: -f2-)"; then
				return 0
			else
				return 1
			fi
		else
			fail "Invalid stream selection strategy: '$1'. Abandoning."
			exit 1
		fi
	}

	# Take care of the audio streams.
	ffAudioStreams="$(ffprobe -show_streams -select_streams a "$inputFile" 2>/dev/null)"
	if [ "$?" != 0 ]; then
		fail "ffprobe failed to read audio information from '$inputFile'"
		return 1
	fi
	audioStreamsMkvMergeCommand=()
	currentStreamZeroBasedIndex=0
	audioStreamsFound=false
	while echo "$ffAudioStreams" | grep -qxF '[STREAM]'; do
		# Extract audio stream information.
		currentStream="$(echo "$ffAudioStreams" | sed -e '/\[\/STREAM\]/,$d')"
		currentStreamIndex="$(echo "$currentStream" | grep '^index=' | cut -d= -f2)"
		if [ -z "$currentStreamIndex" ]; then
			fail "Cannot parse index from audio stream in '$inputFile'."
			return 1
		fi
		currentStreamExtractedFile="$tempAudioDirectory/extracted-$currentStreamIndex"
		currentStreamConvertedFile="$tempAudioDirectory/converted-$currentStreamIndex.mka"
		currentStreamTitle="$(echo "$currentStream" | grep '^TAG:title=' | cut -d= -f2-)"
		currentStreamStartPts="$(echo "$currentStream" | grep '^start_pts=' | cut -d= -f2)"
		currentStreamLanguage="$(echo "$currentStream" | grep '^TAG:language=' | cut -d= -f2-)"
		currentStreamDefault="$(echo "$currentStream" | grep '^DISPOSITION:default=' | cut -d= -f2)"
		currentStreamForced="$(echo "$currentStream" | grep '^DISPOSITION:forced=' | cut -d= -f2)"
		currentStreamLogInfo="audio track at index $currentStreamIndex of file '$inputFile'"

		if streamMatchesRules "$AUDIO_SELECT_STRATEGY" "$currentStreamZeroBasedIndex"; then
			echo "Taking care of $currentStreamLogInfo..."
			if [ -n "$currentStreamTitle" ]; then
				audioStreamsMkvMergeCommand+=(--track-name "0:$currentStreamTitle")
			fi
			if [ -n "$currentStreamStartPts" ]; then
				audioStreamsMkvMergeCommand+=(--sync "0:$currentStreamStartPts")
			fi
			if [ -n "$currentStreamLanguage" ]; then
				audioStreamsMkvMergeCommand+=(--language "0:$currentStreamLanguage")
			fi
			if [ -n "$currentStreamDefault" ]; then
				audioStreamsMkvMergeCommand+=(--default-track "0:$currentStreamDefault")
			fi
			if [ -n "$currentStreamForced" ]; then
				audioStreamsMkvMergeCommand+=(--forced-track "0:$currentStreamForced")
			fi
			audioStreamsMkvMergeCommand+=(--no-track-tags --no-global-tags "$currentStreamConvertedFile")

			# Extract audio stream.
			if ! mkvextract tracks "$inputFile" "$currentStreamIndex:$currentStreamExtractedFile"; then
				fail "Could not extract $currentStreamLogInfo."
				return 1
			fi
			currentStreamIsFlac=false
			if ffprobe -show_streams -select_streams a "$currentStreamExtractedFile" | grep -qxF 'codec_name=flac'; then
				currentStreamIsFlac=true
			fi

			# Process audio stream.
			currentStreamFilter=''
			if [ "$edActuallyRemove" == true -a "$opActuallyRemove" == true ]; then
				# Remove both OP and ED.
				interOpEd="$(python3 -c "print(${edBeginFadeBeginTimestamp}-${opEndFadeBeginTimestamp})")"
				currentStreamFilter="[0:a]atrim=duration=${opBeginFadeEndTimestamp},afade=t=out:st=${opBeginFadeBeginTimestamp}:d=${opBeginFadeDuration}[beforeop];[0:a]atrim=start=${opEndFadeBeginTimestamp},asetpts=PTS-STARTPTS,afade=t=in:d=${opEndFadeDuration},afade=t=out:st=${interOpEd}:d=${edBeginFadeDuration}[middle];[0:a]atrim=start=${edEndFadeBeginTimestamp},asetpts=PTS-STARTPTS,afade=t=in:d=${edEndFadeDuration}[aftered];[beforeop][middle]concat=v=0:a=1[beforeed];[beforeed][aftered]concat=v=0:a=1[out]"
			elif [ "$edActuallyRemove" == true ]; then
				# Remove only ED.
				currentStreamFilter="[0:a]atrim=duration=${edBeginFadeEndTimestamp},afade=t=out:st=${edBeginFadeBeginTimestamp}:d=${edBeginFadeDuration}[beforeed];[0:a]atrim=start=${edEndFadeBeginTimestamp},asetpts=PTS-STARTPTS,afade=t=in:d=${edEndFadeDuration}[aftered];[beforeed][aftered]concat=v=0:a=1[out]"
			elif [ "$opActuallyRemove" == true ]; then
				# Remove only OP.
				currentStreamFilter="[0:a]atrim=duration=${opBeginFadeEndTimestamp},afade=t=out:st=${opBeginFadeBeginTimestamp}:d=${opBeginFadeDuration}[beforeop];[0:a]atrim=start=${opEndFadeBeginTimestamp},asetpts=PTS-STARTPTS,afade=t=in:d=${opEndFadeDuration}[afterop];[beforeop][afterop]concat=v=0:a=1[out]"
			fi
			currentStreamFilterComplex=()
			if [ -n "$currentStreamFilter" ]; then
				currentStreamFilterComplex=(-filter_complex "$currentStreamFilter" -map '[out]')
			fi
			if [ "$currentStreamIsFlac" != true -o "${#currentStreamFilterComplex[@]}" -ne 0 ]; then
				# < /dev/null required as per http://unix.stackexchange.com/a/36411
				if ! ffmpeg -y -i "$currentStreamExtractedFile" -acodec flac -t "$outputTotalDuration" "${currentStreamFilterComplex[@]}" "$currentStreamConvertedFile" < /dev/null; then
					fail "Could not convert extracted $currentStreamLogInfo."
				fi
			else
				# Just copy it.
				cp "$currentStreamExtractedFile" "$currentStreamConvertedFile"
			fi
			rm -f "$currentStreamExtractedFile"
			audioStreamsFound=true
		else
			echo "Skipping $currentStreamLogInfo (does not match strategy)"
		fi

		# Iterate.
		ffAudioStreams="$(echo "$ffAudioStreams" | sed -e '1,/\[\/STREAM\]/d')"
		currentStreamZeroBasedIndex="$(expr "$currentStreamZeroBasedIndex" + 1)"
	done
	if [ "$AUDIO_MUST_MATCH" == true -a "$AUDIO_SELECT_STRATEGY" != 'none' -a "$audioStreamsFound" != true -a "$currentStreamZeroBasedIndex" -gt 0 ]; then
		fail "Could not find a matching audio stream for strategy '$AUDIO_SELECT_STRATEGY'."
		return 1
	fi

	# Take care of attachment streams.
	attachmentStreamsMkvMergeCommand=()
	while read -r currentStream; do
		# Extract attachment stream information.
		currentStreamIndex="$(echo "$currentStream" | sed -r "s/^Attachment ID ([0-9]+):.*\$/\\1/g")"
		if [ -z "$currentStreamIndex" ]; then
			fail "Cannot parse index from audio stream in '$inputFile'."
			return 1
		fi
		currentStreamExtractedFile="$tempAttachmentsDirectory/extracted-$currentStreamIndex"
		currentStreamMimeType="$(echo "$currentStream" | sed -r "s/^Attachment ID [0-9]+: type '([^']+)'.*\$/\\1/g")"
		if [ -n "$currentStreamMimeType" ]; then
			attachmentStreamsMkvMergeCommand+=(--attachment-mime-type "$currentStreamMimeType")
		fi
		currentStreamFilename="$(echo "$currentStream" | sed -r "s/^Attachment ID [0-9]+: type '[^']+', size [0-9]+ bytes, file name '(.+)'\$/\\1/g")"
		if [ -z "$currentStreamFilename" ]; then
			fail "Cannot get filename of attachment at index '$currentStreamIndex' in '$inputFile'."
			return 1
		fi
		currentSteamIsFont=false
		for fontExtension in "${fontExtensions[@]}"; do
			if echo "$currentStreamFilename" | grep -qi "^.*\\.$fontExtension\$"; then
				currentSteamIsFont=true
				break
			fi
		done
		currentStreamLogInfo="attachment '$currentStreamFilename' at index $currentStreamIndex of file '$inputFile'"
		echo "Taking care of $currentStreamLogInfo..."
		attachmentStreamsMkvMergeCommand+=(--attachment-name "$currentStreamFilename" --attach-file "$currentStreamExtractedFile")

		# Extract attachment stream.
		if ! mkvextract attachments "$inputFile" "$currentStreamIndex:$currentStreamExtractedFile"; then
			fail "Could not extract $currentStreamLogInfo."
			return 1
		fi

		# If it's a font, register it.
		if [ "$currentSteamIsFont" == true ]; then
			currentStreamFontFilename="$(echo "$currentStreamFilename" | tr '[:upper:]' '[:lower:]')"
			currentStreamFontFile="$tempAttachmentsFontsDirectory/$currentStreamFontFilename"
			# currentStreamFontInstalledFile is not always accurate.
			# The font filename is not kept the same once moved to the Fonts folder or merged with an existing font file.
			currentStreamFontInstalledFile="$wineFonts/$currentStreamFontFilename"
			cleanupFiles+=("$currentStreamFontFile" "$currentStreamFontInstalledFile")
			# Remove potentially-already-installed version. Might be a corefont!
			pushd "$wineFonts" &> /dev/null
				find -iname "$currentStreamFontFile" -delete
			popd &> /dev/null
			echo "Registering '$currentStreamFontFile' from $currentStreamLogInfo..."
			cp -a "$currentStreamExtractedFile" "$currentStreamFontFile"
			pushd "$tempAttachmentsFontsDirectory" &> /dev/null
				if ! "$wineBinary" "$fontregBinary" /move; then
					echo "Failed to register '$currentStreamFontFile' from $currentStreamLogInfo into wine prefix."
					popd &> /dev/null
					return 1
				fi
			popd &> /dev/null
			# Kill leftovers in case fontreg didn't do what it was supposed to do.
			rm -f "$currentStreamFontFile"
		fi
	done < <(mkvmerge --identify "$inputFile" | grep -P '^Attachment ID [0-9]+:')

	# Take care of the subtitle streams.
	ffSubtitleStreams="$(ffprobe -show_streams -select_streams s "$inputFile" 2>/dev/null)"
	if [ "$?" != 0 ]; then
		fail "ffprobe failed to read subtitles from '$inputFile'"
		return 1
	fi

	subtitleStreamsMkvMergeCommand=()
	subtitleStreamsFilesToMerge=()
	currentStreamZeroBasedIndex=0
	currentStreamInjectionZeroBasedIndex=0
	subtitleStreamsFound=false
	injectedSubtitleFile=''
	currentStreamInjectedFile=''
	if [ "$SUB_INJECT" == true -a \( "$SUB_INJECT_MERGE_STRATEGY" != none -o "$SUB_INJECT_SEPARATE" == true \) ]; then
		# Determine file to inject.
		injectedSubtitleFile="$(getClosestFile "$inputFile" "$SUB_INJECT_DIRECTORY")"
		if [ -z "$injectedSubtitleFile" ]; then
			if [ "$SUB_MUST_INJECT" == true ]; then
				fail "Sub injection must succeed, but could not find a matching subtitle file for '$inputFile' in '$SUB_INJECT_DIRECTORY'."
				return 1
			else
				echo "Could not find a matching subtitle file for '$inputFile' in '$SUB_INJECT_DIRECTORY'. No subs will be injected."
			fi
		else
			echo "Selected subtitle file '$injectedSubtitleFile' for injection in '$inputFile'."
		fi
		currentStreamInjectedFile="$tempSubtitlesDirectory/injection.ass"
		cp "$injectedSubtitleFile" "$currentStreamInjectedFile"
		if [ "$edActuallyRemove" == true -a "$SUB_INJECT_DIRECTORY_INCLUDESED" == true ]; then
			if ! "$processSubtitles" --operation remove --begin "$edBeginFadeEndTimestamp" --end "$edEndFadeBeginTimestamp" --file "$currentStreamInjectedFile"; then
				fail "Failed to remove ED from injection-target subtitle file '$injectedSubtitleFile' for '$inputFile'."
				return 1
			fi
		fi
		if [ "$opActuallyRemove" == true -a "$SUB_INJECT_DIRECTORY_INCLUDESOP" == true ]; then
			if ! "$processSubtitles" --operation remove --begin "$opBeginFadeEndTimestamp" --end "$opEndFadeBeginTimestamp" --file "$currentStreamInjectedFile"; then
				fail "Failed to remove OP from injection-target subtitle file '$injectedSubtitleFile' for '$inputFile'."
				return 1
			fi
		fi
		# Check if we need to separately inject subtitles.
		if [ "$SUB_INJECT_SEPARATE" == true ]; then
			subtitleStreamsMkvMergeCommand+=(
				--track-name "0:$(basename "$injectedSubtitleFile" | cutExtension)"
				--default-track '0:true'
				--forced-track '0:false'
			)
			if [ -n "$SUB_INJECT_LANGUAGE" ]; then
				subtitleStreamsMkvMergeCommand+=(--language "0:$SUB_INJECT_LANGUAGE")
			fi
			subtitleStreamsMkvMergeCommand+=(--no-track-tags --no-global-tags "$currentStreamInjectedFile")
		fi
	fi
	while echo "$ffSubtitleStreams" | grep -qxF '[STREAM]'; do
		# Extract subtitle stream information.
		currentStream="$(echo "$ffSubtitleStreams" | sed -e '/\[\/STREAM\]/,$d')"
		currentStreamIndex="$(echo "$currentStream" | grep '^index=' | cut -d= -f2)"
		if [ -z "$currentStreamIndex" ]; then
			fail "Cannot parse index from subtitle stream in '$inputFile'."
			return 1
		fi
		currentStreamExtractedFile="$tempSubtitlesDirectory/extracted-$currentStreamIndex"
		# FIXME: Support SRT!
		currentStreamConvertedFile="$tempSubtitlesDirectory/converted-$currentStreamIndex.ass"
		currentStreamTitle="$(echo "$currentStream" | grep '^TAG:title=' | cut -d= -f2-)"
		currentStreamStartPts="$(echo "$currentStream" | grep '^start_pts=' | cut -d= -f2)"
		currentStreamLanguage="$(echo "$currentStream" | grep '^TAG:language=' | cut -d= -f2-)"
		currentStreamDefault="$(echo "$currentStream" | grep '^DISPOSITION:default=' | cut -d= -f2)"
		currentStreamForced="$(echo "$currentStream" | grep '^DISPOSITION:forced=' | cut -d= -f2)"
		currentStreamLogInfo="subtitle track at index $currentStreamIndex of file '$inputFile'"

		if streamMatchesRules "$SUB_SELECT_STRATEGY" "$currentStreamZeroBasedIndex"; then
			echo "Taking care of $currentStreamLogInfo..."
			if [ "$BURN_SUBTITLES" != true ]; then # "false" or "both"
				if [ -n "$currentStreamTitle" ]; then
					subtitleStreamsMkvMergeCommand+=(--track-name "0:$currentStreamTitle")
				fi
				if [ -n "$currentStreamStartPts" ]; then
					subtitleStreamsMkvMergeCommand+=(--sync "0:$currentStreamStartPts")
				fi
				if [ -n "$currentStreamLanguage" ]; then
					subtitleStreamsMkvMergeCommand+=(--language "0:$currentStreamLanguage")
				fi
				if [ -n "$currentStreamDefault" ]; then
					subtitleStreamsMkvMergeCommand+=(--default-track "0:$currentStreamDefault")
				fi
				if [ -n "$currentStreamForced" ]; then
					subtitleStreamsMkvMergeCommand+=(--forced-track "0:$currentStreamForced")
				fi
				subtitleStreamsMkvMergeCommand+=(--no-track-tags --no-global-tags "$currentStreamConvertedFile")
			fi
			subtitleStreamsFilesToMerge+=("$currentStreamConvertedFile")

			# Extract subtitle stream.
			if ! mkvextract tracks "$inputFile" "$currentStreamIndex:$currentStreamExtractedFile"; then
				fail "Could not extract $currentStreamLogInfo."
				return 1
			fi

			# Remove OP/ED.
			cp -a "$currentStreamExtractedFile" "$currentStreamConvertedFile"
			if [ "$edActuallyRemove" == true ]; then
				if ! "$processSubtitles" --operation remove --begin "$edBeginFadeEndTimestamp" --end "$edEndFadeBeginTimestamp" --file "$currentStreamConvertedFile"; then
					fail "Failed to remove ED from $currentStreamLogInfo."
					return 1
				fi
			fi
			if [ "$opActuallyRemove" == true ]; then
				if ! "$processSubtitles" --operation remove --begin "$opBeginFadeEndTimestamp" --end "$opEndFadeBeginTimestamp" --file "$currentStreamConvertedFile"; then
					fail "Failed to remove OP from $currentStreamLogInfo."
					return 1
				fi
			fi

			# Check for subtitles to inject.
			if [ -n "$injectedSubtitleFile" ] && streamMatchesRules "$SUB_INJECT_MERGE_STRATEGY" "$currentStreamInjectionZeroBasedIndex"; then
				# Merge with main subtitle file.
				currentStreamConvertedFileTemp="$currentStreamConvertedFile.temp_copy_for_injection"
				cp -a "$currentStreamConvertedFile" "$currentStreamConvertedFileTemp"
				if ! "$submergerBinary" --exclude "$SUB_INJECT_EXCLUDE" "$currentStreamConvertedFileTemp" "$currentStreamInjectedFile" > "$currentStreamConvertedFile"; then
					fail "Could not merge injection-target subtitle file '$injectedSubtitleFile' (--exclude '$SUB_INJECT_EXCLUDE') with $currentStreamLogInfo."
					return 1
				fi
				echo "Successfully injected subtitles '$injectedSubtitleFile' into $currentStreamLogInfo."
			fi

			subtitleStreamsFound=true
			currentStreamInjectionZeroBasedIndex="$(expr "$currentStreamInjectionZeroBasedIndex" + 1)"
		else
			echo "Skipping $currentStreamLogInfo (does not match strategy)"
		fi

		# Iterate.
		ffSubtitleStreams="$(echo "$ffSubtitleStreams" | sed -e '1,/\[\/STREAM\]/d')"
		currentStreamZeroBasedIndex="$(expr "$currentStreamZeroBasedIndex" + 1)"
	done
	if [ "$SUB_MUST_MATCH" == true -a "$SUB_SELECT_STRATEGY" != 'none' -a "$subtitleStreamsFound" != true -a "$currentStreamZeroBasedIndex" -gt 0 ]; then
		fail "Could not find a matching subtitle stream for strategy '$SUB_SELECT_STRATEGY'."
		return 1
	fi
	# Check for subtitles to burn.
	actuallyBurnSubtitles=false
	if [ "$BURN_SUBTITLES" != false -a "${#subtitleStreamsFilesToMerge[@]}" -gt 0 ]; then
		if ! "$submergerBinary" "${subtitleStreamsFilesToMerge[@]}" > "$burnedSubtitlesFile"; then
			fail "Could not merge subtitle files ${subtitleStreamsFilesToMerge[@]} for burning."
			return 1
		fi
		actuallyBurnSubtitles=true
	fi

	# Take care of the video stream.
	cleanupFiles+=("$wineInputFile.ffindex" "$wineInputFile" "$avs2yuvInputFile" "$burnedSubtitlesFile")
	rm -f "$wineInputFile.ffindex" "$wineInputFile" "$avs2yuvInputFile"
	if ! ln -s "$inputFile" "$wineInputFile"; then
		fail "Could not create symlink from '$wineInputFile' to '$inputFile'"
		return 1
	fi
	template="$(cat "$avsTemplate")"
	if [ "$INTERFRAME_ENABLE" == true ]; then
		template="$(echo "$template" | sed -r 's/^\s*%IFINTERFRAME%\s*//g')"
	else
		template="$(echo "$template" | sed -r 's/^\s*%IFINTERFRAME%.*$//g')"
	fi
	template="$(echo "$template" | sed "s/%AVISYNTHCORES%/$halfCores/g")"
	template="$(echo "$template" | sed "s/%MAXMEMORYMB%/$AVISYNTH_MEMORY_MB/g")"
	template="$(echo "$template" | sed "s/%INTERFRAMEPRESET%/$INTERFRAME_PRESET/g")"
	template="$(echo "$template" | sed "s/%INPUTFPSNUMERATOR%/$inputFpsNumerator/g")"
	template="$(echo "$template" | sed "s/%INPUTFPSDENOMINATOR%/$inputFpsDenominator/g")"
	template="$(echo "$template" | sed "s/%OUTPUTFPSNUMERATOR%/$outputFpsNumerator/g")"
	template="$(echo "$template" | sed "s/%OUTPUTFPSDENOMINATOR%/$outputFpsDenominator/g")"
	if [ -n "$OUTPUT_HEIGHT" -a "$inputHeight" != "$OUTPUT_HEIGHT" ]; then
		template="$(echo "$template" | sed -r 's/^\s*%IFRESIZE%\s*//g')"
		template="$(echo "$template" | sed "s/%OUTPUTHEIGHT%/$OUTPUT_HEIGHT/g")"
	else
		template="$(echo "$template" | sed -r 's/^\s*%IFRESIZE%.*$//g')"
	fi
	template="$(echo "$template" | sed "s/%HEIGHT%/$OUTPUT_HEIGHT/g")"
	template="$(echo "$template" | sed "s/%PLUGINS%/$(echo "$aviSynthPluginsDirWindows" | sed 's/\\/\\\\/g')/g")"
	if [ "$opActuallyRemove" == true ]; then
		template="$(echo "$template" | sed -r 's/^\s*%IFREMOVEOP%\s*//g')"
		template="$(echo "$template" | sed "s/%OPBEGINFADEENDFRAME%/$opBeginFadeEndFrame/g")"
		template="$(echo "$template" | sed "s/%OPBEGINFADEFRAMECOUNT%/$opBeginFadeFrameCount/g")"
		template="$(echo "$template" | sed "s/%OPENDFADEBEGINFRAME%/$opEndFadeBeginFrame/g")"
		template="$(echo "$template" | sed "s/%OPENDFADEFRAMECOUNT%/$opEndFadeFrameCount/g")"
	else
		template="$(echo "$template" | sed -r 's/^\s*%IFREMOVEOP%.*$//g')"
	fi
	if [ "$edActuallyRemove" == true ]; then
		template="$(echo "$template" | sed -r 's/^\s*%IFREMOVEED%\s*//g')"
		template="$(echo "$template" | sed "s/%EDBEGINFADEENDFRAME%/$edBeginFadeEndFrame/g")"
		template="$(echo "$template" | sed "s/%EDBEGINFADEFRAMECOUNT%/$edBeginFadeFrameCount/g")"
		template="$(echo "$template" | sed "s/%EDENDFADEBEGINFRAME%/$edEndFadeBeginFrame/g")"
		template="$(echo "$template" | sed "s/%EDENDFADEFRAMECOUNT%/$edEndFadeFrameCount/g")"
	else
		template="$(echo "$template" | sed -r 's/^\s*%IFREMOVEED%.*$//g')"
	fi
	if [ "$actuallyBurnSubtitles" == true ]; then
		template="$(echo "$template" | sed -r 's/^\s*%IFBURNSUBTITLES%\s*//g')"
		template="$(echo "$template" | sed "s/%BURNEDSUBTITLESFILE%/C:\\\\$wineInputBurnedSubtitlesFilename/g")"
	else
		template="$(echo "$template" | sed -r 's/^\s*%IFBURNSUBTITLES%.*$//g')"
	fi
	template="$(echo "$template" | sed "s/%INPUTFILE%/C:\\\\$wineInputFilename/g")"
	echo "$template" > "$avs2yuvInputFile"
	if ! "$wineBinary" "$avs2yuvBinary" "$avs2yuvInputWindowsFile" - | x264 "${x264Flags[@]}" --sar "$sampleAspectRatio" -o "$temporaryVideoFile" --stdin y4m -; then
		fail 'Could not encode video.'
		return 1
	fi

	# Take care of transferring important tags (title etc.) over.
	extraMkvMergeCommand=()
	if [ -n "$inputTitle" ]; then
		extraMkvMergeCommand+=(--title "$inputTitle")
	fi

	# Mux it all back together.
	rm -f "$tempMuxingFile"
	inputVideoTracks="$(mkvmerge -i "$inputFile" | grep -P '^Track ID [0-9]+: video' || true)"
	if [ -z "$inputVideoTracks" ]; then
		echo "Error: Cannot find video tracks in '$inputFile'"
		exit 1
	fi
	if [ "$(echo "$inputVideoTracks" | wc -l)" -gt 1 ]; then
		echo "Error: More than one video track in '$inputFile'"
		exit 1
	fi
	inputVideoTrack="$(echo "$inputVideoTracks" | cut -d' ' -f3 | cut -d: -f1)"
	inputFileSegmentUIDs="$(mkvinfo "$inputFile" | grep -P '^\| \+ Segment UID: ')"
	if [ -z "$inputFileSegmentUIDs" ]; then
		echo "Error: Cannot find segment UIDs in '$inputFile'"
		exit 1
	fi
	if [ "$(echo "$inputFileSegmentUIDs" | wc -l)" -gt 1 ]; then
		echo "Error: More than one segment in '$inputFile'"
		exit 1
	fi
	inputFileSegmentUID="$(echo "$inputFileSegmentUIDs" | cut -d: -f2 | sed 's/^ *//')"
	returnCode=0
	if mkvmerge \
			-o "$tempMuxingFile" \
			--segment-uid "$inputFileSegmentUID" \
			--no-audio --no-subtitles --no-buttons --no-track-tags --no-chapters --no-attachments --no-global-tags "$temporaryVideoFile" \
			"${audioStreamsMkvMergeCommand[@]}" \
			"${subtitleStreamsMkvMergeCommand[@]}" \
			"${attachmentStreamsMkvMergeCommand[@]}" \
			--no-track-tags --no-global-tags "${chaptersMkvMergeCommand[@]}" \
			"${extraMkvMergeCommand[@]}"; then
			# + Input file: --no-video --no-audio --no-subtitles --no-chapters "$inputFile"
		mv "$tempMuxingFile" "$outputFile"
	else
		returnCode=1
	fi
	cleanup
	return "$returnCode"
}

processFile() {
	file="$1"
	reloadDefaultConfig
	if [ -f "$configFile" ]; then
		echo "Loading values from '$configFile'."
		source "$configFile"
	else
		echo "Warning: No config file defined. Using default values."
	fi
	for perDirOverrideConfigFile in "${PERDIR_OVERRIDE_CONFIGS[@]}"; do
		inputFilePerDirConfiguration="$(dirname "$file")/$perDirOverrideConfigFile"
		if [ -f "$inputFilePerDirConfiguration" ]; then
			echo "Overriding configuration with per-dir configuration file '$inputFilePerDirConfiguration'"
			export MAKEITSMOOTH_THIS_FILE="$inputFilePerDirConfiguration"
			source "$inputFilePerDirConfiguration"
			unset MAKEITSMOOTH_THIS_FILE
		fi
	done
	halfCores="$(($CORES/2))"
	x264Flags=(
		--profile "$X264_PROFILE"
		--preset "$X264_PRESET"
		--tune "$X264_TUNE"
		--threads "$halfCores"
		"${X264_FLAGS[@]}"
	)
	if [ ! -d "$OUTPUT_DIR" ]; then
		mkdir -p "$OUTPUT_DIR"
	fi
	outputDir="$(cd "$OUTPUT_DIR" && pwd)"
	echo "Processing file '$file'..."
	outputFile="$outputDir/$(basename "$file")"
	if [ -f "$outputFile" ]; then
		echo "Warning: Output file '$outputFile' already exists. Skipping input file '$file'."
		return 0
	fi
	echo "> Final configuration for '$file':"
	echo "   > Output dir:  $OUTPUT_DIR"
	if [ "$INTERFRAME_ENABLE" == true ]; then
		if [ -n "$OUTPUT_FPS_MULTIPLIER" ]; then
			echo "   > Output FPS:  (Input FPS) x $OUTPUT_FPS_MULTIPLIER"
		else
			echo "   > Output FPS:  $OUTPUT_FPS_NUMERATOR/$OUTPUT_FPS_DENOMINATOR (~$(python3 -c "print(round(float($OUTPUT_FPS_NUMERATOR)/float($OUTPUT_FPS_DENOMINATOR), 3))") Hz)"
		fi
	else
		echo "   > Output FPS:  Unmodified"
	fi
	if [ -n "$OUTPUT_HEIGHT" ]; then
		echo "   > Output size: (Keep aspect ratio) x $OUTPUT_HEIGHT pixels"
	else
		echo "   > Output size: Unmodified"
	fi
	if [ "$INTERFRAME_ENABLE" == true ]; then
		echo "   > Cores:       $CORES ($halfCores for AviSynth, $halfCores for x264)"
		echo "   > InterFrame:  $INTERFRAME_PRESET preset"
	fi
	echo "   > x264:        ${x264Flags[@]}"
	if [ "$BURN_SUBTITLES" == true ]; then
		echo "   > Burn subs:   Yes, and don't include them in the container"
	elif [ "$BURN_SUBTITLES" == both ]; then
		echo "   > Burn subs:   Yes, and include them in the container as non-default, non-forced tracks"
	else
		echo "   > Burn subs:   No"
	fi
	if [ "$SUB_INJECT" == true ]; then
		echo "   > Inject subs: Yes"
	else
		echo "   > Inject subs: No"
	fi
	if [ "$REMOVE_OP" == true ]; then
		echo "   > Remove OP:   Yes"
	else
		echo "   > Remove OP:   No"
	fi
	if [ "$REMOVE_ED" == true ]; then
		echo "   > Remove ED:   Yes"
	else
		echo "   > Remove ED:   No"
	fi
	intermediateOutputDir="$outputDir/.$(basename "$file").tmp"
	convert "$file" "$intermediateOutputDir" "$outputFile"
}

while [ -n "$1" ]; do
	if [ "$1" == '-c' -o "$1" == '--config' ]; then
		shift
		configFile="$1"
		shift
		continue
	fi
	if [ -f "$1" ]; then
		processFile "$(readlink -f "$1")"
	elif [ -d "$1" ]; then
		actualDir="$(cd "$1" && pwd)"
		while IFS= read -d $'\0' -r file; do
			processFile "$file"
		done < <(find "$actualDir" -name '*.mkv' -print0 | sort --zero-terminated)
	else
		echo "Error: '$1' does not exist or is not a file/directory."
		exit 1
	fi
	shift
done
