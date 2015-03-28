# Set resource limits.
SetMemoryMax(%MAXMEMORYMB%)
SetMTMode(3, %AVISYNTHCORES%)

# FFMS2.
LoadPlugin("%PLUGINS%\ffms2.dll")
Import("%PLUGINS%\FFMS2.avsi")

%IFINTERFRAME% # SVP.
%IFINTERFRAME% LoadPlugin("%PLUGINS%\svpflow1.dll")
%IFINTERFRAME% LoadPlugin("%PLUGINS%\svpflow2.dll")

%IFBURNSUBTITLES% # xy-VSFilter.
%IFBURNSUBTITLES% LoadPlugin("%PLUGINS%\VSFilter.dll")

%IFINTERFRAME% # InterFrame.
%IFINTERFRAME% Import("%PLUGINS%\InterFrame2.avsi")

# Video source.
FFVideoSource("%INPUTFILE%", fpsnum=%INPUTFPSNUMERATOR%, fpsden=%INPUTFPSDENOMINATOR%)

# Set multithreading mode.
SetMTMode(2)

# Convert to YUV.
ConvertToYV12()

%IFRESIZE% # Nice resizing filter.
%IFRESIZE% SincResize(round(float(width) / float(height) * %OUTPUTHEIGHT%.0 / 4.0) * 4, %OUTPUTHEIGHT%)

%IFINTERFRAME% # Actual motion interpolation.
%IFINTERFRAME% InterFrame(Cores=%AVISYNTHCORES%, Tuning="%INTERFRAMEPRESET%", NewNum=%OUTPUTFPSNUMERATOR%, NewDen=%OUTPUTFPSDENOMINATOR%)
%IFINTERFRAMEPLACEBO% # No motion interpolation, but change framerate anyway.
%IFINTERFRAMEPLACEBO% ChangeFPS(%OUTPUTFPSNUMERATOR%, %OUTPUTFPSDENOMINATOR%)

%IFREMOVEED% # Remove ED.
%IFREMOVEED% edClipBefore = Trim(0, %EDBEGINFADEENDFRAME%).FadeOut0(%EDBEGINFADEFRAMECOUNT%)
%IFREMOVEED% edClipAfter = Trim(%EDENDFADEBEGINFRAME%, 0).FadeIn0(%EDENDFADEFRAMECOUNT%)
%IFREMOVEED% edClipBefore ++ edClipAfter

%IFREMOVEOP% # Remove OP.
%IFREMOVEOP% opClipBefore = Trim(0, %OPBEGINFADEENDFRAME%).FadeOut0(%OPBEGINFADEFRAMECOUNT%)
%IFREMOVEOP% opClipAfter = Trim(%OPENDFADEBEGINFRAME%, 0).FadeIn0(%OPENDFADEFRAMECOUNT%)
%IFREMOVEOP% opClipBefore ++ opClipAfter

%IFBURNSUBTITLES% # Burn subtitles. Resize 2x for antialias.
%IFBURNSUBTITLES% burnSubWidth = last.Width
%IFBURNSUBTITLES% burnSubHeight = last.Height
%IFBURNSUBTITLES% PointResize(burnSubWidth * 2, burnSubHeight * 2)
%IFBURNSUBTITLES% TextSub("%BURNEDSUBTITLESFILE%")
%IFBURNSUBTITLES% BilinearResize(burnSubWidth, burnSubHeight)
