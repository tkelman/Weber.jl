__precompile__()

module Weber

# helper function for clean info and warn output
function cleanstr(strs...;width=70)
  nlines = 0
  ncolumns = 0
  words = (w for str in strs for w in split(str,r"\s+"))
  reduce(words) do result,word
    if ncolumns + length(word) > width
      ncolumns = 0
      nlines += 1
      result *= "\n"
    else
      ncolumns += length(word) + 1
      result *= " "
    end

    result*word
  end
end

try
  @assert sizeof(Int) == 8
catch
  error("Weber can only be run as a 64-bit program. Please use a 64-bit ",
        "implementation of Julia.")
end

old = pwd()
try
  cd(Pkg.dir("Weber"))

  suffix = (success(`git diff-index HEAD --quiet`) ? "" : "-dirty")
  if !isempty(suffix)
    warn(cleanstr("Source files in $(Pkg.dir("Weber")) have been modified",
                  "without being committed to git. Your experiment will not",
                  "be reproduceable."))
  end
  global const version =
    convert(VersionNumber,chomp(readstring(`git describe --tags`))*suffix)
catch
  try
    global const version = Pkg.installed("Weber")
  catch
    warn(cleanstr("The Weber version number could not be determined.",
         "Your experiment will not be reproducable.",
         "It is recommended that you install Weber via Pkg.add(\"Weber\")."))
  end
finally
  cd(old)
end

# load binary library dependencies
depsjl = joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")
if isfile(depsjl)
  include(depsjl)
else
  error("Weber not properly installed. "*
        "Please run\nPkg.build(\"Weber\")")
end

# setup error reporting functions (these are the only calls to SDL that occur
# all that often, so they're the only calls I've wrapped directly).
SDL_GetError() = unsafe_string(ccall((:SDL_GetError,_psycho_SDL2),Cstring,()))
Mix_GetError = SDL_GetError
TTF_GetError = SDL_GetError

# this is a simple function for accessing aribtrary offsets in memory as any
# bitstype you want... this is used to read from a c union by determining the
# offset of various fields in the data using offsetof(struct,field) in c and
# then using that offset to access the memory in julia. SDL's
# core event type (SDL_Event) is a c union.
function at{T}(x::Ptr{Void},::Type{T},offset)
  unsafe_wrap(Array,reinterpret(Ptr{T},x + offset),1)[1]
end

import FileIO: load, save
export load, save

const sdl_is_setup = Array{Bool}()
sdl_is_setup[] = false

include(joinpath(dirname(@__FILE__),"video.jl"))
include(joinpath(dirname(@__FILE__),"sound.jl"))

include(joinpath(dirname(@__FILE__),"types.jl"))
include(joinpath(dirname(@__FILE__),"event.jl"))
include(joinpath(dirname(@__FILE__),"trial.jl"))
include(joinpath(dirname(@__FILE__),"experiment.jl"))

include(joinpath(dirname(@__FILE__),"primitives.jl"))
include(joinpath(dirname(@__FILE__),"helpers.jl"))

include(joinpath(dirname(@__FILE__),"precompile.jl"))

function __init__()
  _precompile_()
  init_events()
end

end
