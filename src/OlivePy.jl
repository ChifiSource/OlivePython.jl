"""
Created in October, 2023 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
by team
[toolips](https://github.com/orgs/ChifiSource/teams/toolips)
This software is MIT-licensed.
#### OlivePy
The OlivePy extension is used to allow `Olive` to edit Python. Editing Python can be done 
in Julia files via Python cells and in Python files themselves.
"""
module OlivePython
using Olive
using Olive.Pkg: add
using Olive.Toolips
using Olive.ToolipsSession
using Olive.ToolipsDefaults
using Olive.ToolipsMarkdown
using Olive.IPyCells
using PyCall
import Olive: build, evaluate, cell_highlight!, getname, olive_save, ProjectExport, olive_read
import Base: string
using Olive: Project, Directory
#==
code/none
==#
#--
function build(c::Connection, cm::ComponentModifier, cell::Cell{:python}, proj::Project{<:Any})
    tm = c[:OliveCore].client_data[getname(c)]["highlighters"]["python"]
    ToolipsMarkdown.clear!(tm)
    ToolipsMarkdown.set_text!(tm, cell.source)
    mark_python!(tm)
    builtcell::Component{:div} = Olive.build_base_cell(c, cm, cell,
    proj, sidebox = true, highlight = true)
    km = Olive.cell_bind!(c, cell, proj)
    interior = builtcell[:children]["cellinterior$(cell.id)"]
    sideb = interior[:children]["cellside$(cell.id)"]
    style!(sideb, "background-color" => "green")
    inp = interior[:children]["cellinput$(cell.id)"]
    inp[:children]["cellhighlight$(cell.id)"][:text] = string(tm)
    bind!(c, cm, inp[:children]["cell$(cell.id)"], km)
    builtcell::Component{:div}
end
#==
code/none
==#
#--
function evaluate(c::Connection, cm::ComponentModifier, cell::Cell{:python}, proj::Project{<:Any})
        cells = proj[:cells]
        # get code
        rawcode::String = replace(cm["cell$(cell.id)"]["text"], "<div>" => "", "<br>" => "\n")
        mod = proj[:mod]
        exec = "PyCall.@py_str(\"\"\"$rawcode\"\"\")"
        println(exec)
        used = true
        try
            getfield(mod, :PyCall)
        catch
            used = false
        end
        execcode::String = *("begin\n", exec, "\nend\n")
        # get project
        ret::Any = ""
        p = Pipe()
        err = Pipe()
        standard_out::String = ""
        redirect_stdio(stdout = p, stderr = err) do
            try
                if used == false
                    mod.evalin(Meta.parse("using PyCall"))
                end
                ret = mod.evalin(Meta.parse(execcode))
            catch e
                ret = e
            end
        end
        close(err)
        close(Base.pipe_writer(p))
        standard_out = replace(read(p, String), "\n" => "<br>")
        outp::String = ""
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
            new_cell = Cell(length(cells) + 1, "python", "")
            push!(cells, new_cell)
            append!(cm, proj.id, build(c, cm, new_cell, proj))
            focus!(cm, "cell$(new_cell.id)")
            return
        else
            new_cell = cells[pos + 1]
        end
end
#==
code/none
==#
#--
function cell_highlight!(c::Connection, cm::ComponentModifier, cell::Cell{:python}, proj::Project{<:Any})
    cell.source = cm["cell$(cell.id)"]["text"]
    tm = c[:OliveCore].client_data[getname(c)]["highlighters"]["python"]
    tm.raw = cell.source
    ToolipsMarkdown.set_text!(tm, cell.source)
    mark_python!(tm)
    set_text!(cm, "cellhighlight$(cell.id)", string(tm))
    ToolipsMarkdown.clear!(tm)
end
#==
code/none
==#
#--
build(c::Connection, om::OliveModifier, oe::OliveExtension{:python}) = begin
    hlighters = c[:OliveCore].client_data[getname(c)]["highlighters"]
    hlighting = c[:OliveCore].client_data[getname(c)]["highlighting"]
    if ~("python" in keys(hlighting))
        c[:Logger].log("loading `PyCall` for `OlivePy` (first start)")
        add("PyCall")
        tm = ToolipsMarkdown.TextStyleModifier("")
        highlight_python!(tm)
        push!(hlighters, "python" => tm)
        push!(hlighting, 
        "python" => Dict{String, String}([string(k) => string(v[1][2]) for (k, v) in tm.styles]))
    end
    if ~("python" in keys(hlighters))
        tm = ToolipsMarkdown.TextStyleModifier("")
        tm.styles = Dict(begin
            Symbol(k[1]) => ["color" => k[2]]
        end for k in c[:OliveCore].client_data[getname(c)]["highlighting"]["python"])
        push!(c[:OliveCore].client_data[getname(c)]["highlighters"], 
        "python" => tm)
        
    end
end
#==
code/none
==#
#--
function mark_python!(tm::ToolipsMarkdown.TextStyleModifier)
    ToolipsMarkdown.mark_between!(tm, "\"\"\"", :multistring)
    ToolipsMarkdown.mark_between!(tm, "\"", :string)
    ToolipsMarkdown.mark_before!(tm, "(", :funcn, until = [" ", "\n", ",", ".", "\"", "&nbsp;",
    "<br>", "("])
    ToolipsMarkdown.mark_all!(tm, "def", :func)
    [ToolipsMarkdown.mark_all!(tm, string(dig), :number) for dig in digits(1234567890)]
    ToolipsMarkdown.mark_all!(tm, "True", :number)
    ToolipsMarkdown.mark_all!(tm, "import", :import)
    ToolipsMarkdown.mark_all!(tm, ":", :number)
    ToolipsMarkdown.mark_all!(tm, "False", :number)
    ToolipsMarkdown.mark_all!(tm, "elif", :if)
    ToolipsMarkdown.mark_all!(tm, "pass", :keyword)
    ToolipsMarkdown.mark_all!(tm, "as", :keyword)
    ToolipsMarkdown.mark_all!(tm, "if", :if)
    ToolipsMarkdown.mark_all!(tm, "else", :if)
    ToolipsMarkdown.mark_all!(tm, "del", :keyword)
    ToolipsMarkdown.mark_all!(tm, "in", :keyword)

end
#==
code/none
==#
#--
function highlight_python!(tm::ToolipsMarkdown.TextStyleModifier)
    style!(tm, :multistring, ["color" => "darkgreen"])
    style!(tm, :string, ["color" => "green"])
    style!(tm, :func, ["color" => "#fc038c"])
    style!(tm, :funcn, ["color" => "#8b0000"])
    style!(tm, :if, ["color" => "#fc038c"])
    style!(tm, :number, ["color" => "#8b0000"])
    style!(tm, :import, ["color" => "#fc038c"])
    style!(tm, :keyword, ["color" => "#fc038c"])
    style!(tm, :default, ["color" => "#3D3D3D"])
end
#==
code/none
==#
#--
function read_py(uri::String)
    pyd = split(read(uri, String), "\n\n")
    [Cell(e, "python", string(line)) for (e, line) in enumerate(pyd)]
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
function olive_save(cells::Vector{<:IPyCells.AbstractCell}, p::Project{<:Any}, 
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
