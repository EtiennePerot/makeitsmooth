# `makeitsmooth`

Increases the framerate of video files through [motion interpolation][Motion interpolation]. Basically a command-line (thus automatable!) version of [this tutorial][Convert videos to 60fps].

Uses [InterFrame] for motion interpolation (which itself uses the [SVP] libraries), running with [AviSynth] under [Wine], and then piped to [x264] and finally remuxed together (using [mkvmerge][mkvtoolnix]) with the rest of the input file (which stays untouched).

## Sample output

See the sample videos on [Spirton's tutorial][Convert videos to 60fps]. This uses the same method with similar options, so the results will look pretty much like that.

## Usage

	$ ./makeitsmooth n1 n2 ... [-c configfile2 n3 n4 n5 ... [-c configfile3 n6 n7 ...]]
	    In the above line, n1 and n2 would be processed using the default configuration file ./config,
	    n3, n4 and n5 would be processed using configfile2, and n6, n7 would be processed using configfile3.
	    nX can be an mkv file, or a directory which will be resursively searched for *.mkv files.

On first use, the script will grab a bunch of things to set up the Wine prefix with all the required Windows-y software. Everything will go under `scratch` next to the script.

Do not run multiple instances of this at the same time. You will run into trouble. Instead, queue the directories in a single execution.

## Configuration

	$ cp config.sample config
	$ $EDITOR config

Edit the variables as you see fit:

* `OUTPUT_DIR`: Output directory. All output files will be placed there.
* `OUTPUT_FPS_NUMERATOR` / `OUTPUT_FPS_DENOMINATOR`: Set the target framerate. The final framerate will be the ratio of these two numbers. For 60.0 Hz, simply use `60` and `1`.
* `OUTPUT_HEIGHT`: Resulting height of the video, in pixels. Default is `1080` pixels. The video width is rounded to the nearest multiple of 4.
* `CORES`: Number of cores to use to process the video. Must be an even number. This is divided by 2 when passed to InterFrame and x264. This way, if you have `CORES=4`, then there will be 2 InterFrame threads and 2 x264 threads. This is also used for `make -jX` for compiling Wine. This number is then doubled (2 jobs per core).
* `INTERFRAME_PRESET`: Name of the InterFrame preset. Possible values are `Film`, `Animation` (cartoons/anime), `Smooth`, `Weak`, or `Placebo`. Refer to [InterFrame's documentation] for info on these. `Placebo` doesn't use InterFrame; instead, it just uses AviSynth's ChangeFPS function, with no motion interpolation.
* `X264_PROFILE`, `X264_PRESET`, `X264_TUNE`: Values for the x264 `--profile`, `--preset`, and `--tune` parameters.
* `X264_FLAGS`: Extra flags you wish to pass to x264.


## Assumptions

* All your video files are in Matroska format.
* There is exactly one **video track**. It's OK to have multiple non-video tracks.
* The aforementioned single video track has constant framerate.
* There is exactly one **segment** per file. This has nothing to do with multiple "chapters"; those are OK too. If you have no idea what a segment is, you'll be fine.
* All your video files are uniquely-named (their converted versions all get shoved in the same output directory).
* You want H.264 video output.
* You are OK with lossily re-encoding your files. (You keep the originals though, so if you want you can just generate the high-framerate ones on-demand whenever you want to watch them, and then delete them afterwards.)

## Features

* Supports arbitrary number of non-video streams per file.
* Supports attachments (subtitle fonts, etc) and other metadata.
* Segment UIDs and chapter information are copied from the original file, so segment linking will keep working. (aka: Your external OPs/EDs will still work fine.)

## Dependencies

* Basics: `unzip`, `tar`, `7z`, `wget`, `python`
* All of Wine's build dependencies (`pacman -Qi wine` / `apt-get build-dep wine`)
* x264
* mkvtoolnix suite (`mkvmerge`, `mkvinfo`)

## Licensing

`makeitsmooth.sh` is licensed under the WTFPL.

## TODO

* Preserve video title (`mkvmerge --title`).
* Support running multiple instances at the same time.

[Motion interpolation]: https://en.wikipedia.org/wiki/Motion_interpolation
[Convert videos to 60fps]: http://www.spirton.com/convert-videos-to-60fps/
[InterFrame]: http://www.spirton.com/interframe/
[SVP]: http://www.svp-team.com/
[AviSynth]: http://avisynth.nl/
[Wine]: http://www.winehq.org/
[x264]: https://www.videolan.org/developers/x264.html
[mkvtoolnix]: http://www.bunkus.org/videotools/mkvtoolnix/
