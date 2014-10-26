#!/usr/bin/env bash

set -e

# These are overridable by the config file.
OUTPUT_DIR='/tmp/smooth'
OUTPUT_FPS_NUMERATOR=60
OUTPUT_FPS_DENOMINATOR=1
OUTPUT_HEIGHT=1080
CORES="$(nproc)"
INTERFRAME_PRESET='Animation'
X264_PROFILE='high10'
X264_TUNE='animation'
X264_PRESET='slow'
X264_FLAGS='--crf 21 --qpmin 10 --qpmax 51'

# These are not.
scriptDir="$(dirname "$BASH_SOURCE")"
scriptDir="$(cd "$scriptDir" && pwd)"
configFile="$scriptDir/config"
resourceDir="$scriptDir/res"
scratchDir="$scriptDir/scratch"
wineTar='wine-1.7.12.tar.bz2'
filesRoot='Files-20131216'
filesZip="$filesRoot.zip"
avs2yuvExe='avs2yuv.exe'
ffms2Root='ffms2-2.18-rc1'
ffms27z="$ffms2Root.7z"
resources=(
	"http://mirrors.ibiblio.org/wine/source/1.7/$wineTar|142def53c2e7e46418fd37426232d1524f09c73b"
	"http://www.spirton.com/uploads/60FPS/$filesZip|010ec724a9bdbb40414ed0f737da1112133ffb9a"
	"http://akuvian.org/src/avisynth/avs2yuv/$avs2yuvExe|4abe0de0ec66d8fe43910ba7794b837512bff1fc"
	"https://ffmpegsource.googlecode.com/files/$ffms27z|f2d68b5f67d74c73e9707a0919fe594be49a2168"
)
wineDir="$scratchDir/wine"
wineBuildDir="$wineDir/build"
wineBinary="$wineBuildDir/wine"
winePrefix="$wineDir/prefix"
wineDriveC="$winePrefix/drive_c"
wineProgramFiles1="$wineDriveC/Program Files (x86)"
wineProgramFiles2="$wineDriveC/Program Files"
filesExtract="$scratchDir/$filesRoot"
filesAviSynthSetup="$filesExtract/AviSynth.exe"
filesAviSynthPlugins="$filesExtract/tools/avisynth_plugin"
avs2yuvBinary="$resourceDir/$avs2yuvExe"
ffms2Extract="$scratchDir/$ffms2Root"
ffms2Plugins=("$ffms2Extract/FFMS2.avsi" "$ffms2Extract/x86/ffms2.dll")
avsTemplate="$scriptDir/template.avs"
wineInputFilename='__input.mkv'
avs2yuvInputFilename='input.avs'

if [ -z "$1" ]; then
	echo "Usage: $0 n1 n2 ... [-c configfile2 n3 n4 n5 ... [-c configfile3 n6 n7 ...]]"
	echo " In the above line, n1 and n2 would be processed using the default configuration file '$configFile',"
	echo ' n3, n4 and n5 would be processed using configfile2, and n6, n7 would be processed using configfile3.'
	echo ' nX can be an mkv file, or a directory which will be resursively searched for *.mkv files.'
	exit 0
fi

echo 'Making sure we have all resources...'
for res in "${resources[@]}"; do
	url="$(echo "$res" | cut -d '|' -f 1)"
	sha1="$(echo "$res" | cut -d '|' -f 2)"
	path="$resourceDir/$(basename "$url")"
	while [ ! -f "$path" -o "$(sha1sum "$path" | cut -d ' ' -f 1 || true)" != "$sha1" ]; do
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
	pushd "$wineBuildDir"
		tar xf "$resourceDir/$wineTar" --strip-components=1
		./configure
		make -j"$(($CORES * 2))"
	popd
	if [ ! -x "$wineBinary" ]; then
		echo 'Error: Wine compilation failed.'
		exit 1
	fi
fi
export WINEPREFIX="$winePrefix"

echo 'Taking care of extracting the files...'
if [ ! -d "$filesExtract" ]; then
	pushd "$scratchDir"
		unzip "$resourceDir/$filesZip"
	popd
	if [ ! -d "$filesExtract" ]; then
		echo 'Error: Failed to extract files from zip.'
		exit 1
	fi
fi

echo 'Taking care of FFMS2...'
if [ ! -d "$ffms2Extract" ]; then
	pushd "$scratchDir"
		7z x "$resourceDir/$ffms27z"
	popd
	if [ ! -d "$ffms2Extract" ]; then
		echo 'Error: Failed to extract files from ffms2.'
		exit 1
	fi
fi

echo 'Taking care of AviSynth...'
aviSynthInstallDir="$wineDriveC/Program Files (x86)/AviSynth"
if [ ! -d "$wineProgramFiles1/AviSynth" -a ! -d "$wineProgramFiles2/AviSynth" ]; then
	echo 'Please install it in the default directory.'
	"$wineBinary" "$filesAviSynthSetup"
fi
aviSynthDir="$wineProgramFiles1/AviSynth"
aviSynthPluginsDirWindows='C:\Program Files (x86)\AviSynth\plugins'
if [ ! -d "$aviSynthDir" ]; then
	if [ ! -d "$wineProgramFiles2/AviSynth" ]; then
		echo 'Error: Cannot find installed AviSynth.'
		exit 1
	else
		aviSynthDir="$wineProgramFiles2/AviSynth"
		aviSynthPluginsDirWindows='C:\Program Files\AviSynth\plugins'
	fi
fi
cp --no-clobber "$filesAviSynthPlugins"/* "${ffms2Plugins[@]}" "$aviSynthDir/plugins"
wineInputFile="$wineDriveC/$wineInputFilename"
avs2yuvInputFile="$wineDriveC/$avs2yuvInputFilename"
avs2yuvInputWindowsFile="C:\\$avs2yuvInputFilename"

echo 'Ready to start.'

convert() {
	inputFile="$1"
	intermediateOutputFile="$2"
	rm -f "$wineInputFile.ffindex" "$wineInputFile" "$avs2yuvInputFile" "$intermediateOutputFile" # Remove leftover cruft
	ln -s "$inputFile" "$wineInputFile"
	template="$(cat "$avsTemplate")"
	template="$(echo "$template" | sed "s/%CORES%/$halfCores/g")"
	template="$(echo "$template" | sed "s/%INTERFRAMEPRESET%/$INTERFRAME_PRESET/g")"
	template="$(echo "$template" | sed "s/%FPSNUMERATOR%/$OUTPUT_FPS_NUMERATOR/g")"
	template="$(echo "$template" | sed "s/%FPSDENOMINATOR%/$OUTPUT_FPS_DENOMINATOR/g")"
	template="$(echo "$template" | sed "s/%HEIGHT%/$OUTPUT_HEIGHT/g")"
	template="$(echo "$template" | sed "s/%PLUGINS%/$(echo "$aviSynthPluginsDirWindows" | sed 's/\\/\\\\/g')/g")"
	template="$(echo "$template" | sed "s/%INPUTFILE%/C:\\\\$wineInputFilename/g")"
	echo "$template" > "$avs2yuvInputFile"
	"$wineBinary" "$avs2yuvBinary" "$avs2yuvInputWindowsFile" - | x264 $x264Flags -o "$intermediateOutputFile" --stdin y4m -
	rm -f "$wineInputFile.ffindex" "$wineInputFile" "$avs2yuvInputFile"
}

remux() {
	inputFile="$1"
	convertedFile="$2"
	outputFile="$3"
	tempOutputFile="$3.tmp"
	rm -f "$tempOutputFile"
	inputVideoTracks="$(mkvmerge -i "$inputFile" | grep -P '^Track ID [0-9]+: video' || true)"
	if [ -z "$inputVideoTracks" ]; then
		echo "Error: Cannot find video tracks in '$inputFile'"
		exit 1
	fi
	if [ "$(echo "$inputVideoTracks" | wc -l)" -gt 1 ]; then
		echo "Error: More than one video track in '$inputFile'"
		exit 1
	fi
	inputVideoTrack="$(echo "$inputVideoTracks" | cut -d ' ' -f 3 | cut -d ':' -f 1)"
	inputFileSegmentUIDs="$(mkvinfo "$inputFile" | grep -P '^\| \+ Segment UID: ')"
	if [ -z "$inputFileSegmentUIDs" ]; then
		echo "Error: Cannot find segment UIDs in '$inputFile'"
		exit 1
	fi
	if [ "$(echo "$inputFileSegmentUIDs" | wc -l)" -gt 1 ]; then
		echo "Error: More than one segment in '$inputFile'"
		exit 1
	fi
	inputFileSegmentUID="$(echo "$inputFileSegmentUIDs" | cut -d : -f 2 | sed 's/^ *//')"
	if ! mkvmerge \
			-o "$tempOutputFile" \
			--segment-uid "$inputFileSegmentUID" \
			--no-audio --no-subtitles --no-buttons --no-track-tags --no-chapters --no-attachments --no-global-tags "$convertedFile" \
			--no-video "$inputFile"; then
		rm -f "$tempOutputFile"
		exit 1
	else
		mv "$tempOutputFile" "$outputFile"
	fi
}

processFile() {
	file="$1"
	echo "Processing file '$file'..."
	outputFile="$outputDir/$(basename "$file")"
	if [ -f "$outputFile" ]; then
		echo "Warning: File '$outputFile' already exists. Skipping."
		continue
	fi
	intermediateOutputFile="$outputDir/.$(basename "$file").tmp.264"
	convert "$file" "$intermediateOutputFile"
	remux "$file" "$intermediateOutputFile" "$outputFile"
	rm "$intermediateOutputFile"
}

while [ -n "$1" ]; do
	if [ "$1" == '-c' -o "$1" == '--config' ]; then
		shift
		configFile="$1"
		shift
		continue
	fi
	if [ -f "$configFile" ]; then
		echo "Loading values from '$configFile'."
		source "$configFile"
	else
		echo "Warning: No config file at '$configFile'. Continuing with previous/default values."
	fi
	halfCores="$(($CORES/2))"
	x264Flags="--profile $X264_PROFILE --preset $X264_PRESET --tune $X264_TUNE --threads $halfCores $X264_FLAGS"
	echo "> Final configuration for '$1':"
	echo "   > Output dir: $OUTPUT_DIR"
	echo "   > Output FPS: $OUTPUT_FPS_NUMERATOR/$OUTPUT_FPS_DENOMINATOR (~$(python -c "print(round(float($OUTPUT_FPS_NUMERATOR)/float($OUTPUT_FPS_DENOMINATOR), 3))") Hz)"
	echo "   > Cores:      $CORES ($halfCores InterFrame, $halfCores x264)"
	echo "   > InterFrame: $INTERFRAME_PRESET preset"
	echo "   > x264:       $x264Flags"
	if [ ! -d "$OUTPUT_DIR" ]; then
		mkdir -p "$OUTPUT_DIR"
	fi
	outputDir="$(cd "$OUTPUT_DIR" && pwd)"
	if [ -f "$1" ]; then
		processFile "$1"
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
