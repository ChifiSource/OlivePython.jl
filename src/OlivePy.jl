module OlivePy
using Olive
using Olive.Toolips
using Olive.ToolipsSession
using Olive.ToolipsDefaults
using Olive.ToolipsMarkdown
using PyCall
import Olive: build, evaluate, cell_highlight!
import Base: string
using Olive: Project, Directory

function build(c::Connection, cm::ComponentModifier, cell::Cell{:python},
    cells::Vector{Cell}, proj::Project{<:Any})
    tm = ToolipsMarkdown.TextStyleModifier(cell.source)
    python_block!(tm)
    builtcell::Component{:div} = Olive.build_base_cell(c, cm, cell, cells,
    proj, sidebox = true, highlight = true)
    km = Olive.cell_bind!(c, cell, cells, proj)
    interior = builtcell[:children]["cellinterior$(cell.id)"]
    sideb = interior[:children]["cellside$(cell.id)"]
    style!(sideb, "background-color" => "green")
    inp = interior[:children]["cellinput$(cell.id)"]
    inp[:children]["cellhighlight$(cell.id)"][:text] = string(tm)
    bind!(c, cm, inp[:children]["cell$(cell.id)"], km)
    builtcell::Component{:div}
end

function evaluate(c::Connection, cm2::ComponentModifier, cell::Cell{:python},
    cells::Vector{Cell}, proj::Project{<:Any})
    icon = Olive.olive_loadicon()
    cell_drag = Olive.topbar_icon("cell$(cell.id)drag", "drag_indicator")
    cell_run = Olive.topbar_icon("cell$(cell.id)drag", "play_arrow")
    style!(cell_drag, "color" => "white", "font-size" => 17pt)
    style!(cell_run, "color" => "white", "font-size" => 17pt)
    on(c, cell_run, "click") do cm2::ComponentModifier
        evaluate(c, cm2, cell, cells, proj)
    end
    icon.name = "load$(cell.id)"
    icon["width"] = "20"
    remove!(cm2, cell_run)
    set_children!(cm2, "cellside$(cell.id)", [icon])
    script!(c, cm2, "$(cell.id)eval") do cm::ComponentModifier
        # get code
        rawcode::String = cm["cell$(cell.id)"]["text"]]
        mod = proj[:mod]
        exec = "PyCall.@py_str(\"\"\"$rawcode\"\"\")"
        used = true
        try
            getfield(mod, :PyCall)
        catch
            used = false
        end
        execcode::String = *("begin\n", exec, "\nend\n")
        # get project
        selected::String = cm["olivemain"]["selected"]
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
        set_children!(cm, "cellside$(cell.id)", [cell_drag, br(), cell_run])
        set_text!(cm, "cell$(cell.id)out", outp)
        cell.outputs = outp
        pos = findfirst(lcell -> lcell.id == cell.id, cells)
        if pos == length(cells)
            new_cell = Cell(length(cells) + 1, "python", "")
            push!(cells, new_cell)
            append!(cm, proj.id, build(c, cm, new_cell, cells, proj))
            focus!(cm, "cell$(new_cell.id)")
            return
        else
            new_cell = cells[pos + 1]
        end
    end
end

function cell_highlight!(c::Connection, cm::ComponentModifier, cell::Cell{:python},
    cells::Vector{Cell}, proj::Project{<:Any})
    curr = cm["cell$(cell.id)"]["text"]
    cell.source = curr
    tm = ToolipsMarkdown.TextStyleModifier(cell.source)
    python_block!(tm)
    set_text!(cm, "cellhighlight$(cell.id)", string(tm))
end

function python_block!(tm::ToolipsMarkdown.TextStyleModifier)
    ToolipsMarkdown.mark_between!(tm, "\"\"\"", :multistring, exclude = "\"\"\"")
    ToolipsMarkdown.mark_between!(tm, "\"", :string)
    ToolipsMarkdown.mark_all!(tm, "def", :func)
    [ToolipsMarkdown.mark_all!(tm, string(dig), :number) for dig in digits(1234567890)]
    ToolipsMarkdown.mark_all!(tm, "True", :number)
    ToolipsMarkdown.mark_all!(tm, "import ", :import)
    ToolipsMarkdown.mark_all!(tm, ":", :number)
    ToolipsMarkdown.mark_all!(tm, "False", :number)
    ToolipsMarkdown.mark_all!(tm, "elif ", :if)
    ToolipsMarkdown.mark_all!(tm, " if ", :if)
    ToolipsMarkdown.mark_all!(tm, "if ", :if)
    ToolipsMarkdown.mark_all!(tm, "else ", :if)
    ToolipsMarkdown.mark_before!(tm, "(", :funcn, until = [" ", "\n", ",", ".", "\"", "&nbsp;",
    "<br>", "("])
    highlight_python!(tm)
end

function highlight_python!(tm::ToolipsMarkdown.TextStyleModifier)
    style!(tm, :multistring, ["color" => "darkgreen"])
    style!(tm, :string, ["color" => "green"])
    style!(tm, :func, ["color" => "#fc038c"])
    style!(tm, :funcn, ["color" => "red"])
    style!(tm, :if, ["color" => "#fc038c"])
    style!(tm, :number, ["color" => "#8b0000"])
    style!(tm, :import, ["color" => "#fc038c"])
    style!(tm, :default, ["color" => "#3D3D3D"])
end

function read_py(uri::String)
    pyd = split(read(uri, String), "\n\n")
    [Cell(e, "python", string(line)) for (e, line) in enumerate(pyd)]
end

function build(c::Connection, cell::Cell{:py},
    d::Directory{<:Any}; explorer::Bool = false)
    filecell = Olive.build_base_cell(c, cell, d, explorer = explorer)
    style!(filecell, "background-color" => "green", "cursor" => "pointer")
    filecell
end

function py_string(c::Cell{<:Any})
    c.source
end

function py_string(c::Cell{:python})
    c.source
end

function string(c::Cell{:python})
    """py\"\"\"$(c.source)\"\"\"
    #==output[python]
    $(c.outputs)
    ==#
    #==|||==#
    """
end

end # module
