# `makeitsmooth`

Increases the framerate of video files through [motion interpolation][Motion interpolation]. Basically a command-line (thus automatable!) version of [this tutorial][Convert videos to 60fps].

Uses [InterFrame] for motion interpolation (which itself uses the [SVP] libraries), running with [AviSynth] under [Wine], and then piped to [x264] and finally remuxed together (using [mkvmerge][mkvtoolnix]) with the rest of the input file (which stays untouched).

## Sample output

See the sample videos on [Spirton's tutorial][Convert videos to 60fps]. This uses the same method with similar options, so the results will look pretty much like that.

## Usage

	$ ./makeitsmooth.sh dir1 [dir2 [dir3 [...]]]

On first use, the script will grab a bunch of things to set up the Wine prefix with all the required Windows-y software. Everything will go under `scratch` next to the script.

## Configuration

	$ cp config.sample config
	$ $EDITOR config

Edit the variables as you see fit:

* `OUTPUT_DIR`: Output directory. All output files will be placed there.
* `OUTPUT_FPS_NUMERATOR` / `OUTPUT_FPS_DENOMINATOR`: Set the target framerate. The final framerate will be the ratio of these two numbers. For 60.0 Hz, simply use `60` and `1`.
* `CORES`: Number of cores to use to process the video. Must be an even number. This is divided by 2 when passed to InterFrame and x264. This way, if you have `CORES=4`, then there will be 2 InterFrame threads and 2 x264 threads. This is also used for `make -jX` for compiling Wine. This number is then doubled (2 jobs per core).
* `INTERFRAME_PRESET`: Name of the InterFrame preset. Possible values are "Film", "Animation" (cartoons/anime), "Smooth", "Weak". Refer to [InterFrame's documentation] for info on these.
* `X264_PROFILE`, `X264_PRESET`, `X264_TUNE`: Values for the x264 `--profile`, `--preset`, and `--tune` parameters.
* `X264_FLAGS`: Extra flags you wish to pass to x264.


## Assumptions

* All your video files are in Matroska format.
* There is exactly one video **track** and one **segment** per file. This has nothing to do with multiple "chapters"; those are OK. If you have no idea what that means, you'll be fine.
* All your video files are uniquely-named (their converted versions all get shoved in the same output directory).
* You want H.264 video output.

## Features

* Supports arbitrary number of non-video streams per file.
* Supports attachments (subtitle fonts, etc) and other metadata.
* Segment UIDs and chapter information are copied from the original file, so segment linking does not break.

## Dependencies

* Basics: `unzip`, `tar`, `7z`, `wget`, `python`
* All of Wine's build dependencies (`pacman -Qi wine` / `apt-get build-dep wine`)
* x264
* mkvtoolnix suite (`mkvmerge`, `mkvinfo`)

## Licensing

`makeitsmooth.sh` is licensed under the WTFPL.

[Motion interpolation]: https://en.wikipedia.org/wiki/Motion_interpolation
[Convert videos to 60fps]: http://www.spirton.com/convert-videos-to-60fps/
[InterFrame]: http://www.spirton.com/interframe/
[SVP]: http://www.svp-team.com/
[AviSynth]: http://avisynth.nl/
[Wine]: http://www.winehq.org/
[x264]: https://www.videolan.org/developers/x264.html
[mkvtoolnix]: http://www.bunkus.org/videotools/mkvtoolnix/
