SetMemoryMax(512)
SetMTMode(3,%CORES%)

# FFMS2
LoadPlugin("%PLUGINS%\ffms2.dll")
Import("%PLUGINS%\FFMS2.avsi")

# SVP
LoadPlugin("%PLUGINS%\svpflow1.dll")
LoadPlugin("%PLUGINS%\svpflow2.dll")

# InterFrame
Import("%PLUGINS%\InterFrame2.avsi")

FFVideoSource("%INPUTFILE%").ConvertToYV12()
SetMTMode(2)
InterFrame(Cores=%CORES%, Tuning="%INTERFRAMEPRESET%", NewNum=%FPSNUMERATOR%, NewDen=%FPSDENOMINATOR%)
