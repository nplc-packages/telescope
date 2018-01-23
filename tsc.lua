#!/usr/bin/env nplc
NPL.load_package("telescope")
NPL.load_package("luacov")

telescope = NPL.load("telescope")
local SPEC_FILE_PATTERNS = {"_spec.lua$", "_spec.npl$"}
local lfs = commonlib.Files.GetLuaFileSystem()

local function luacov_report()
    local luacov = require("luacov.stats")
    local data = luacov.load("luacov.stats.out")
    if not data then
        print("Could not load stats file " .. luacov.statsfile .. ".")
        print("Run your Lua program with -lluacov and then rerun luacov.")
        os.exit(1)
    end
    local report = io.open("coverage.html", "w")
    report:write("<!DOCTYPE html>", "\n")
    report:write(
        [[
  <html>
  <head>
  <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
  <title>Luacov Coverage Report
  </title>
  <style type="text/css">
    body { text-align: center; }
    #wrapper { width: 800px; margin: auto; text-align: left; }
    pre, ul, li { margin: 0; padding: 0 }
    li { list-style-type: none; font-size: 11px}
    .covered { background-color: #98FB98 }
    .uncovered { background-color: #FFC0CB }
    .file { width: 800px;
      background-color: #c0c0c0;
      padding: 3px;
      overflow: hidden;
      -webkit-border-radius: 5px;
      -moz-border-radius: 5px;
      border-radius: 5px; }
  </style>
  </head>
  <body>
  <div id="wrapper">
  <h1>Luacov Code Coverage Report</h1>
  ]]
    )
    report:write("<p>Generated on ", os.date(), "</p>\n")

    local names = {}
    for filename, _ in pairs(data) do
        table.insert(names, filename)
    end

    local escapes = {
        [">"] = "&gt;",
        ["<"] = "&lt;"
    }
    local function escape_html(str)
        return str:gsub(
            "[<>]",
            function(a)
                return escapes[a]
            end
        )
    end

    table.sort(names)

    for _, filename in ipairs(names) do
        if string.match(filename, "/luacov/") or string.match(filename, "/tsc$") then
            break
        end
        local filedata = data[filename]
        filename = string.gsub(filename, "^%./", "")
        local file = io.open(filename, "r")
        if file then
            report:write("<h2>", filename, "</h2>", "\n")
            report:write("<div class='file'>")
            report:write("<ul>", "\n")
            local line_nr = 1
            while true do
                local line = file:read("*l")
                if not line then
                    break
                end
                if line:match("^%s*%-%-") then -- Comment line
                elseif
                    line:match("^%s*$") or -- Empty line
                        line:match("^%s*end,?%s*$") or -- Single "end"
                        line:match("^%s*else%s*$") or -- Single "else"
                        line:match("^%s*{%s*$") or -- Single opening brace
                        line:match("^%s*}%s*$") or -- Single closing brace
                        line:match("^#!")
                 then -- Unix hash-bang magic line
                    report:write(
                        "<li><pre>",
                        string.format("%-4d", line_nr),
                        "      ",
                        escape_html(line),
                        "</pre></li>",
                        "\n"
                    )
                else
                    local hits = filedata[line_nr]
                    local class = "uncovered"
                    if not hits then
                        hits = 0
                    end
                    if hits > 0 then
                        class = "covered"
                    end
                    report:write(
                        "<li>",
                        " <pre ",
                        "class='",
                        class,
                        "'>",
                        string.format("%-4d", line_nr),
                        string.format("%-4d", hits),
                        "&nbsp;",
                        escape_html(line),
                        "</pre></li>",
                        "\n"
                    )
                end
                line_nr = line_nr + 1
            end
        end
        report:write("</ul>", "\n")
        report:write("</div>", "\n")
    end
    report:write([[
</div>
</body>
</html>
  ]])
end

local function getopt(arg, options)
    local tab = {}
    for k, v in ipairs(arg) do
        if string.sub(v, 1, 2) == "--" then
            local x = string.find(v, "=", 1, true)
            if x then
                tab[string.sub(v, 3, x - 1)] = string.sub(v, x + 1)
            else
                tab[string.sub(v, 3)] = true
            end
        elseif string.sub(v, 1, 1) == "-" then
            local y = 2
            local l = string.len(v)
            local jopt
            while (y <= l) do
                jopt = string.sub(v, y, y)
                if string.find(options, jopt, 1, true) then
                    if y < l then
                        tab[jopt] = string.sub(v, y + 1)
                        y = l
                    else
                        tab[jopt] = arg[k + 1]
                    end
                else
                    tab[jopt] = true
                end
                y = y + 1
            end
        end
    end
    return tab
end

local callbacks = {}

local function progress_meter(t)
    io.stdout:write(t.status_label)
end

local function show_usage()
    local text =
        [[
Telescope

Usage: tsc [options] [files]

Description:
  Telescope is a test framework for Lua that allows you to write tests
  and specs in a TDD or BDD style.

Options:

  -f,     --full            Show full report
  -q,     --quiet           Show don't show any stack traces
  -s      --silent          Don't show any output
  -h,-?   --help            Show this text
  -v      --version         Show version
  -c      --luacov          Output a coverage file using Luacov (http://luacov.luaforge.net/)
          --load=<file>     Load a Lua file before executing command
          --name=<pattern>  Only run tests whose name matches a Lua string pattern

  Callback options:
    --after=<function>        Run function given after each test
    --before=<function>       Run function before each test
    --err=<function>          Run function after each test that produces an error
    --fail<function>          Run function after each failing test
    --pass=<function>         Run function after each passing test
    --pending=<function>      Run function after each pending test
    --unassertive=<function>  Run function after each unassertive test

  An example callback:

    tsc --after="function(t) print(t.status_label, t.name, t.context) end" example.lua

]]
    print(text)
end

local function add_callback(callback, func)
    if callbacks[callback] then
        if type(callbacks[callback]) ~= "table" then
            callbacks[callback] = {callbacks[callback]}
        end
        table.insert(callbacks[callback], func)
    else
        callbacks[callback] = func
    end
end

local function load_spec_files(files, basedir)
    for _, pattern in ipairs(SPEC_FILE_PATTERNS) do
        if (basedir:match(pattern)) then
            print(basedir)
            table.insert(files, basedir)
            return
        end
    end
    for entry in lfs.dir(basedir) do
        if entry ~= "." and entry ~= ".." then
            local path = basedir .. "/" .. entry
            local attr = lfs.attributes(path)
            if (not (type(attr) == "table")) then
                error(format("get attributes of '%s' failed.", path))
            end

            if attr.mode == "directory" then
                load_spec_files(files, path)
            else
                for _, pattern in ipairs(SPEC_FILE_PATTERNS) do
                    if (path:match(pattern)) then
                        table.insert(files, path)
                        break
                    end
                end
            end
        end
    end
end

local function process_args(arg)
    local files = {}
    local opts = getopt(arg, "")
    local i = 1
    for _, _ in pairs(opts) do
        i = i + 1
    end
    for i = i, #arg do
        local basedir = lfs.currentdir() .. "/" .. arg[i]
        load_spec_files(files, basedir)
    end

    return opts, files
end

return function(ctx)
    local opts, files = process_args(ctx.arg)
    if opts["h"] or opts["?"] or opts["help"] or not (next(opts) or next(files)) then
        show_usage()
        return
    end

    if opts.v or opts.version then
        print(telescope.version)
        return
    end

    if opts.c or opts.luacov then
        require "luacov.tick"
    end

    -- load a file with custom functionality if desired
    if opts["load"] then
        dofile(opts["load"])
    end

    local test_pattern
    if opts["name"] then
        test_pattern = function(t)
            return t.name:match(opts["name"])
        end
    end

    -- set callbacks passed on command line
    local callback_args = {
        "after",
        "before",
        "err",
        "fail",
        "pass",
        "pending",
        "unassertive"
    }
    for _, callback in ipairs(callback_args) do
        if opts[callback] then
            add_callback(callback, loadstring(opts[callback])())
        end
    end

    local contexts = {}
    for _, file in ipairs(files) do
        telescope.load_contexts(file, contexts)
    end

    local buffer = {}
    local results = telescope.run(contexts, callbacks, test_pattern)
    local summary, data = telescope.summary_report(contexts, results)

    if opts.f or opts.full then
        table.insert(buffer, telescope.test_report(contexts, results))
    end

    if not opts.s and not opts.silent then
        table.insert(buffer, summary)
        if not opts.q and not opts.quiet then
            local report = telescope.error_report(contexts, results)
            if report then
                table.insert(buffer, "")
                table.insert(buffer, report)
            end
        end
    end

    if #buffer > 0 then
        print(table.concat(buffer, "\n"))
    end

    if opts.c or opts.coverage then
        luacov_report()
        os.remove("luacov.stats.out")
    end

    for _, v in pairs(results) do
        if v.status_code == telescope.status_codes.err or v.status_code == telescope.status_codes.fail then
            return
        end
    end
end
