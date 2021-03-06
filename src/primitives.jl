# TODO: create a 2AFC adaptive abstraction

export instruct, response, addbreak_every, show_cross, @read_args, randomize_by
using ArgParse
using Juno: input, selector
import Juno

"""
    response(key1 => response1,key2 => response2,...;kwds...)

Create a watcher moment that records press of `key[n]` as
`record(response[n];kwds...)`.
"""
function response(responses...;info...)
  begin (event) ->
    for (key,response) in responses
      if iskeydown(event,key)
        record(response;info...)
      end
    end
  end
end

"""
    instruct(str)

Presents some instructions to the participant.

This adds "(Hit spacebar to continue...)" to the end of the text, and waits for
the participant to press spacebar to move on.

"""
function instruct(str)
  text = visual(str*" (Hit spacebar to continue...)")
  m = moment() do t
    record("instructions")
    display(text)
  end
  [m,await_response(iskeydown(key":space:"))]
end

"""
    addbreak_every(n,total,
                   [response=key":space:"],[response_str="the spacebar"])

Adds a break every `n` times this event is added given a known number of
total such events.

By default this waits for the user to hit spacebar to move on.
"""
function addbreak_every(n,total,response=key":space:",
                        response_str="the spacebar")
  meta = experiment_metadata()
  index = meta[:break_every_index] = get(meta,:break_every_index,0) + 1
  if n <= index < total && (n == 1 || index % n == 1)
    message = moment() do t
      record("break")
      display(visual("You can take a break. Hit "*
                     "$response_str when you're ready to resume... "*
                     "$(div(index,n)) of $(div(total,n)-1) breaks."))
    end

    addbreak(message,await_response(e -> iskeydown(e,response)))
  end
end

"""
    show_cross([delta_t])

Creates a moment that shows a cross hair `delta_t` seconds after the start
of the previous moment (defaults to 0 seconds).
"""
function show_cross(delta_t::Number=0;render_options...)
  c = visual("+";render_options...)
  moment(delta_t,t -> display(c))
end

function as_arg(expr)
  if isa(expr,Symbol) || expr.head != :kw
    error("Expected keyword parameters specifying additional program arguments.")
  end

  if isa(expr.args[2],Symbol)
    quote
      $(string(expr.args[1]))
      $(esc(:required)) = true
      $(esc(:arg_type)) = $(expr.args[2])
    end
  elseif expr.args[2].head == :vect
    quote
      $(string(expr.args[1]))
      $(esc(:required)) = true
      $(esc(:arg_type)) = String
      $(esc(:help)) = $(join(map(x -> x.args[1],expr.args[2].args),", "," or "))
    end
  else
    error("Expected keyword value to be a vector of symbols or a type.")
  end
end

function as_arg_checker(expr)
  if !isa(expr.args[2],Symbol) && expr.args[2].head == :vect
    quote
      let str = $(string(expr.args[1])), vals = $(expr.args[2])
        if !any(s -> string(s) == parsed[str],vals)
          println("Expected \"$str\" argument to be "*join(vals,", "," or ")*".")
          println(usage_string(s))
          exit()
        end
      end
    end
  else
    :nothing
  end
end

function as_arg_result(expr)
  if !isa(expr.args[2],Symbol) && expr.args[2].head == :vect
    :(Symbol(parsed[$(string(expr.args[1]))]))
  else
    :(parsed[$(string(expr.args[1]))])
  end
end

"""
    randomize_by(itr)

Randomize by a given iterable object, usually a string (e.g. the subject id.)

If the same string is given, calls to random functions (e.g. `rand`, `randn` and
`shuffle`) will result in the same output.
"""
randomize_by(itr) = srand(reinterpret(UInt32,collect(itr)))

"""
    @read_args(description,[keyword args...])

Reads experimental parameters from the user.

With no additional keyword arguments this requests the subject id, and an
optional `skip` parameter (defaults to 0) from the user, and then returns them
both in a tuple. The skip can be used to restart an experiment by passing it as
the `skip` keyword argument to the `Experiment` constructor. The optional
skip argument is always provided as the final value in the tuple (so if there
are additional keyword arguments, skip will come after these)

You can specify additional keyword arguments to request additional
values from the user. Arguments that are a type will yield a request for
textual input, and will verify that that input can be parased as the given type.
Arguments whose values are a list of symbols yield a request that the user select
one of the specified values.

Arguments are requested from the user either as command-line arguments,
or, if no command-line arguments were specified, interactively. Interactive
arguments work both in the terminal or in Juno. This macro also
generates useful help text that will be displayed to the user
when they give a single command-line "-h" argument. This help text
will print out the `desecription` string.

# Example

    subject_id,condition,block,skip = @read_args("A simple experiment",
      condition=[:red,:green,:blue],block=Int)
"""
macro read_args(description,keys...)
  arg_expr = quote
    "sid"
    $(esc(:help)) = "Subject id. Trials are randomized per subject."
    $(esc(:required)) = true
    $(esc(:arg_type)) = String
  end

  for arg_body in map(as_arg,keys)
    for line in arg_body.args
      push!(arg_expr.args,line)
    end
  end

  skip_expr = quote
    "skip"
    $(esc(:help)) = "# of offsets to skip. Useful for restarting in middle of experiment."
    $(esc(:required)) = false
    $(esc(:arg_type)) = Int
    $(esc(:default)) = 0
  end
  arg_expr.args = vcat(arg_expr.args,skip_expr.args)

  arg_body = quote
    s = ArgParseSettings(description = $(esc(description)))

    @add_arg_table s begin
      $arg_expr
    end

    parsed = parse_args(ARGS,s)
  end


  for line in map(as_arg_checker,keys)
    push!(arg_body.args,line)
  end

  result_tuple = :((parsed["sid"],parsed["skip"]))
  for result = map(as_arg_result,keys)
    push!(result_tuple.args,result)
  end
  push!(arg_body.args,result_tuple)

  readline_call = :(readline_args())
  for k in keys
    push!(readline_call.args,k)
  end

  quote
    cd(dirname(@__FILE__))
    if length(ARGS) > 0
      $arg_body
    else
      $readline_call
    end
  end
end

function readline_args(;keys...)
  print("Enter subject id: ")
  sid = chomp(input())
  args = Array{Any}(length(keys))
  for (i,(kw,value)) in enumerate(keys)
    if isa(value,Type)
      if Juno.isactive()
        println("Enter $kw: ")
      else
        print("Enter $kw: ")
      end
      args[i] = parse(value,input())
    else
      if Juno.isactive()
        println("Enter $kw: ")
        args[i] = selector(value)
      else
        print("Enter $kw ($(join(map(string,value),", "," or "))): ")
        args[i] = chomp(readline())
        if Symbol(args[i]) ∉ value
          error("Expected $kw to be $(join(map(string,value),", "," or ")) "*
                "but got $(args[i]).")
        end
      end
    end
  end
  print("Offset to start at? (default = 0): ")
  str = input()
  if isempty(chomp(str))
    skip = 0
  else
    skip = parse(Int,str)
  end
  println("Running...")
  (sid,skip,args...)
end
