"""
Created in October, 2023 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
by team
[toolips](https://github.com/orgs/ChifiSource/teams/toolips)
This software is MIT-licensed.
#### OlivePython
The `OlivePython` extension allows `Olive` to edit and evaluate Python code! Editing Python can be done 
in Julia files via Python cells and in Python files themselves.
"""
module OlivePython
using Olive
using Olive.Pkg: add
using Olive.Toolips
using Olive.ToolipsSession
using Olive.Toolips.Components
using Olive.OliveHighlighters
using Olive.IPyCells
using PyCall
import Olive: build, evaluate, cell_highlight!, getname, olive_save, olive_read, get_highlighter
import Base: string
using Olive: Project, Directory, Cell, ComponentModifier, OliveExtension, ProjectExport
#==
code/none
==#
#--
function build(c::Connection, cm::ComponentModifier, cell::Cell{:python}, proj::Project{<:Any})
    tm = c[:OliveCore].users[getname(c)]["highlighters"]["python"]
    OliveHighlighters.clear!(tm)
    OliveHighlighters.set_text!(tm, cell.source)
    mark_python!(tm)
    builtcell::Component{:div} = Olive.build_base_cell(c, cm, cell,
    proj, sidebox = true, highlight = true)
    km = Olive.cell_bind!(c, cell, proj)
    interior = builtcell[:children]["cellinterior$(cell.id)"]
    sideb = interior[:children]["cellside$(cell.id)"]
    style!(sideb, "background-color" => "green")
    inp = interior[:children]["cellinput$(cell.id)"]
    inp[:children]["cellhighlight$(cell.id)"][:text] = string(tm)
    Components.bind(c, cm, inp[:children]["cell$(cell.id)"], km)
    builtcell::Component{:div}
end
#==
code/none
==#
#--
function evaluate(c::Connection, cm::ComponentModifier, cell::Cell{:python}, proj::Project{<:Any})
        cells = proj[:cells]
        # get code
        p = Pipe()
        err = Pipe()
        standard_out::String = ""
        rawcode::String = replace(cm["cell$(cell.id)"]["text"], "<div>" => "", "<br>" => "\n")
        mod = proj[:mod]
        exec = "PyCall.@py_str(\"\"\"$rawcode\n\"\"\")"
        used = true
        try
            getfield(mod, :PyCall)
        catch
            used = false
        end
        execcode::String = *("begin\n", exec, "\nend\n")
        ret::Any = ""
        redirect_stdio(stdout = p, stderr = err) do
            # begin STDIO redirect
        # get project
        try
            if used == false
                try
                    mod.evalin(Meta.parse("using PyCall"))
                catch
                    Olive.Pkg.activate(Olive.CORE.data["home"])
                    mod.evalin(Meta.parse("using PyCall"))
                end
            end
            ret = mod.evalin(Meta.parse(execcode))
        catch e
            ret = e
        end
        end # STDO redirect
        outp::String = ""
        close(err)
        close(Base.pipe_writer(p))
        standard_out = replace(read(p, String), "\n" => "<br>")
        od = Olive.OliveDisplay()
        if typeof(ret) <: Exception
            Base.showerror(od.io, ret)
            outp = replace(String(od.io.data), "\n" => "</br>")
        elseif ~(isnothing(ret)) && length(standard_out) > 0
            display(od, MIME"olive"(), ret)
            outp = standard_out * "</br>" * String(od.io.data)
        elseif ~(isnothing(ret)) && length(standard_out) == 0
            display(od, MIME"olive"(), ret)
            outp = String(od.io.data)
        else
            outp = standard_out
        end
        set_text!(cm, "cell$(cell.id)out", outp)
        cell.outputs = outp
        pos = findfirst(lcell -> lcell.id == cell.id, cells)
        if pos == length(cells)
            new_cell = Cell("python", "")
            push!(cells, new_cell)
            append!(cm, proj.id, build(c, cm, new_cell, proj))
            focus!(cm, "cell$(new_cell.id)")
            return
        else
            new_cell = cells[pos + 1]
        end
end

function get_highlighter(c::Connection, cell::Cell{:python})
    c[:OliveCore].users[getname(c)].data["highlighters"]["python"]
end

#==
code/none
==#
#--
function cell_highlight!(c::Connection, cm::ComponentModifier, cell::Cell{:python}, proj::Project{<:Any})
    cell.source = cm["cell$(cell.id)"]["text"]
    tm = c[:OliveCore].users[getname(c)].data["highlighters"]["python"]
    tm.raw = cell.source
    mark_python!(tm)
    set_text!(cm, "cellhighlight$(cell.id)", string(tm))
    OliveHighlighters.clear!(tm)
end
#==
code/none
==#
#--
build(c::Connection, om::ComponentModifier, oe::OliveExtension{:python}) = begin
    client_data = c[:OliveCore].users[getname(c)].data
    if ~("highlighters" in keys(client_data))
        om2 = ComponentModifier("")
        Olive.load_style_settings(c, om2)
    end
    hlighters = client_data["highlighters"]
    hlighting = client_data["highlighting"]
    if ~("python" in keys(hlighting))
        add("PyCall")
        tm = OliveHighlighters.TextStyleModifier("")
        highlight_python!(tm)
        push!(hlighters, "python" => tm)
        push!(hlighting, 
        "python" => Dict{String, String}([string(k) => string(v[1][2]) for (k, v) in tm.styles]))
    end
    if ~("python" in keys(hlighters))
        tm = OliveHighlighters.TextStyleModifier("")
        tm.styles = Dict(begin
            Symbol(k[1]) => ["color" => k[2]]
        end for k in client_data["highlighting"]["python"])
        push!(client_data["highlighters"], "python" => tm)
    end
end
#==
code/none
==#
#--
"""
```julia
mark_python!(tm::OliveHighlighters.TextStyleModifier) -> ::Nothing
```
Marks Python code in a `TextStyleModifier`, similar to `mark_julia!` from `OliveHighlighters`.
```julia
tm = TextStyleModifier("def sample(x : int):")
mark_python!(tm)
highlight_python!(tm)

string(tm)
```
- See also: `OlivePython`, `highlight_python!`, `read_py`
"""
function mark_python!(tm::OliveHighlighters.TextStyleModifier)
    OliveHighlighters.mark_between!(tm, "\"\"\"", :multistring)
    OliveHighlighters.mark_between!(tm, "'", :string)
    OliveHighlighters.mark_between!(tm, "\"", :string)
    OliveHighlighters.mark_line_after!(tm, "#", :comment)
    OliveHighlighters.mark_all!(tm, "return", :from)
    OliveHighlighters.mark_before!(tm, "(", :funcn, until = [" ", "\n", ",", ".", "\"", "&nbsp;",
    "<br>", "("])
    OliveHighlighters.mark_all!(tm, "def", :func)
    OliveHighlighters.mark_all!(tm, "float", :datatype)
    OliveHighlighters.mark_all!(tm, "str", :datatype)
    OliveHighlighters.mark_all!(tm, "int", :datatype)
    OliveHighlighters.mark_all!(tm, "bool", :datatype)
    [OliveHighlighters.mark_all!(tm, string(dig), :number) for dig in digits(1234567890)]
    OliveHighlighters.mark_all!(tm, "True", :number)
    OliveHighlighters.mark_all!(tm, "import", :import)
    OliveHighlighters.mark_all!(tm, ":", :number)
    OliveHighlighters.mark_all!(tm, "False", :number)
    OliveHighlighters.mark_all!(tm, "elif", :if)
    OliveHighlighters.mark_all!(tm, "pass", :keyword)
    OliveHighlighters.mark_all!(tm, "as", :keyword)
    OliveHighlighters.mark_all!(tm, "if", :if)
    OliveHighlighters.mark_all!(tm, "else", :if)
    OliveHighlighters.mark_all!(tm, "del", :none)
    OliveHighlighters.mark_all!(tm, "None", :none)
    OliveHighlighters.mark_all!(tm, "in", :keyword)
    OliveHighlighters.mark_all!(tm, "for", :from)
    OliveHighlighters.mark_all!(tm, "from", :from)
    OliveHighlighters.mark_all!(tm, "class", :class)
    OliveHighlighters.mark_all!(tm, "self", :self)
end
#==
code/none
==#
#--
"""
```julia
highlight_python!(tm::OliveHighlighters.TextStyleModifier) -> ::Nothing
```
Highlights Python code in a `TextStyleModifier`.
```julia
tm = TextStyleModifier("def sample(x : int):")
mark_python!(tm)
highlight_python!(tm)

string(tm)
```
- See also: `OlivePython`, `highlight_python!`, `read_py`
"""
function highlight_python!(tm::OliveHighlighters.TextStyleModifier)
    style!(tm, :multistring, ["color" => "#122902"])
    style!(tm, :string, ["color" => "#3c5e25"])
    style!(tm, :func, ["color" => "#fc038c"])
    style!(tm, :funcn, ["color" => "#8b0000"])
    style!(tm, :if, ["color" => "#fc038c"])
    style!(tm, :number, ["color" => "#8b0000"])
    style!(tm, :import, ["color" => "#fc038c"])
    style!(tm, :keyword, ["color" => "#fc038c"])
    style!(tm, :default, ["color" => "#3D3D3D"])
    style!(tm, :self, ["color" => "#990833"])
    style!(tm, :from, ["color" => "#220899"])
    style!(tm, :datatype, ["color" => "#147e8c"])
    style!(tm, :none, ["color" => "#9e6400"])
    style!(tm, :class, ["color" => "#3a107d"])
end
#==
code/none
==#
#--
"""
```julia
read_py(uri::String) -> ::Vector{Cell{<:Any}}
```
Reads a `py` file into notebook cells for `Olive`.
```julia
tm = TextStyleModifier("def sample(x : int):")
mark_python!(tm)
highlight_python!(tm)

string(tm)
```
- See also: `OlivePython`, `highlight_python!`, `read_py`, `py_string`
"""
function read_py(uri::String)
    pyd = split(read(uri, String), "\n\n")
    Vector{Cell}([Cell("python", string(line)) for (e, line) in enumerate(pyd)])
end
#==
code/none
==#
#--
function build(c::Connection, cell::Cell{:py},
    d::Directory{<:Any})
    filecell = Olive.build_base_cell(c, cell, d)
    style!(filecell, "background-color" => "green")
    filecell
end

function olive_read(cell::Cell{:py})
    read_py(cell.outputs)
end

#==
code/none
==#
#--
"""
```julia
py_string(c::Cell{<:Any}) -> ::String
py_string(c::Cell{:python}) -> ::String
```
`py_string` turns a given `Cell` into its `Python` version. The `Cell{<:Any}` dispatch will simply return an empty 
string, removing that cell from the source -- another dispatch could be added to add certain new cell types. 
This is used for the python `Olive.ProjectExport` (`ProjectExport{:py}`)
```julia
function olive_save(p::Project{<:Any}, 
    pe::ProjectExport{:py})
    open(p.data[:path], "w") do o::IO
        write(o, join([py_string(c) for c in p.data[:cells]], "\n\n"))
    end
    nothing
end
```
- See also: `read_py`, `py_string`, `OlivePython`, `Olive`
"""
function py_string(c::Cell{<:Any})
    ""
end
#==
code/none
==#
#--
function py_string(c::Cell{:python})
    c.source
end
#==
code/none
==#
#--
function string(c::Cell{:python})
    """py\"\"\"$(c.source)\"\"\"
    #==out""" * """put[python]
    $(c.outputs)
    ==#
    #==||""" * "|==#"
end
#==
code/none
==#
#--
function olive_save(p::Project{<:Any}, 
    pe::ProjectExport{:py})
    open(p.data[:path], "w") do o::IO
        write(o, join([py_string(c) for c in p.data[:cells]], "\n\n"))
    end
    nothing
end
#==
code/none
==#
#--
end # module
#==output[module]
==#
#==|||==#
